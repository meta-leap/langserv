const dotzig = ".zig";
usingnamespace @import("./_using" ++ [4]u8{ 110, 97, 109, 101 } ++ "space" ++ dotzig);

pub const SrcFile = struct {
    sess: *Session,
    mutex: std.Mutex = std.Mutex.init(),
    id: u64,
    full_path: Str,
    build_zig_dir_path: Str = "",
    ast: struct {
        good: ?*zig_ast.Tree = null, // ==cur if that has no errs, else the most recent good one
        cur: ?*zig_ast.Tree = null,
        checknums: [2]u64 = undefined,
    },
    notes: struct {
        errs: struct {
            load: ?@TypeOf(std.fs.Dir.readFileAlloc).ReturnType.ErrorSet = null,
            parse: usize = 0,
            build: std.ArrayList(Note),
        },
    },
    intel: ?Intel = null,
    direct_importers: std.StringHashMap(void),

    pub var loadFromPath = defaultLoadFromPath;

    pub fn defaultLoadFromPath(mem_alloc: *std.mem.Allocator, src_file_abs_path: Str) !Str {
        return std.fs.cwd().readFileAlloc(mem_alloc, src_file_abs_path, @as(usize, 1024 * 1024 * 1024));
    }

    pub inline fn id(src_file_path: Str) u64 {
        return std.hash.Wyhash.hash(src_file_path.len, src_file_path);
    }

    pub fn deinit(me: *SrcFile) void {
        const lock = me.mutex.acquire();
        defer {
            lock.release();
            me.sess.mem_alloc.destroy(me);
        }
        me.sess.mem_alloc.free(me.full_path);
        me.clearBuildIssues();
        me.notes.errs.build.deinit();
        if (me.intel) |*intel| {
            intel.deinit();
            me.intel = null;
        }
        me.deinitAsts();
        me.direct_importers.deinit();
    }

    fn deinitAsts(me: *SrcFile) void {
        if (me.ast.good) |ast_good| {
            if (me.ast.cur == null or me.ast.cur.? != ast_good) {
                me.sess.mem_alloc.free(ast_good.source);
                ast_good.deinit();
            }
            me.ast.good = null;
        }
        if (me.ast.cur) |ast_cur| {
            me.sess.mem_alloc.free(ast_cur.source);
            ast_cur.deinit();
            me.ast.cur = null;
        }
    }

    pub fn clearBuildIssues(me: *SrcFile) void {
        for (me.notes.errs.build.items[0..me.notes.errs.build.len]) |*build_issue| {
            me.sess.mem_alloc.free(build_issue.message);
            if (build_issue.related_notes) |*related_notes| {
                for (related_notes.items[0..related_notes.len]) |*related_note| {
                    me.sess.mem_alloc.free(related_note.full_file_path);
                    me.sess.mem_alloc.free(related_note.message);
                }
                related_notes.deinit();
            }
        }
        me.notes.errs.build.len = 0;
    }

    pub fn affectedBuildDirs(me: *SrcFile, mem_temp: *std.heap.ArenaAllocator) ![]const Str {
        const lock = me.mutex.acquire();
        defer lock.release();

        var ret = try std.ArrayList(Str).initCapacity(&mem_temp.allocator, 2 * me.direct_importers.count());
        if (me.build_zig_dir_path.len != 0)
            try ret.append(me.build_zig_dir_path);

        var dones = std.StringHashMap(void).init(&mem_temp.allocator);
        var stack = try std.ArrayList(Str).initCapacity(&mem_temp.allocator, me.direct_importers.count());
        {
            var iter = me.direct_importers.iterator();
            while (iter.next()) |direct_importer| if (null == try dones.put(direct_importer.key, {}))
                try stack.append(direct_importer.key);
        }
        while (stack.popOrNull()) |importer| if (me.sess.src_files.getByFullPath(importer)) |src_file|
            if (src_file != me) {
                const lock_file = src_file.mutex.acquire();
                defer lock_file.release();
                if (src_file.build_zig_dir_path.len != 0 and
                    null == zag.mem.indexOf(ret.items[0..ret.len], src_file.build_zig_dir_path, 0, null))
                    try ret.append(src_file.build_zig_dir_path);
                var iter = src_file.direct_importers.iterator();
                while (iter.next()) |direct_importer| if (null == try dones.put(direct_importer.key, {}))
                    try stack.append(direct_importer.key);
            };

        return ret.toSliceConst();
    }

    pub fn formatted(me: *SrcFile, mem_temp: *std.heap.ArenaAllocator) !?Str {
        const lock = me.mutex.acquire();
        defer lock.release();
        if (me.ast.cur) |ast_cur|
            if (ast_cur.errors.len == 0) {
                var buf = try mem_temp.allocator.alloc(u8, ast_cur.source.len * 2);
                var out = std.io.SliceOutStream.init(buf);
                if (std.zig.render(&mem_temp.allocator, &out.stream, ast_cur) catch return null)
                    return out.getWritten(); // try std.mem.dupe(mem, u8, out.getWritten());
            };
        return null;
    }

    pub fn reload(me: *SrcFile, mem_temp: *std.heap.ArenaAllocator) !bool {
        const lock = me.mutex.acquire();
        defer lock.release();

        me.notes.errs.load = null;
        var src: Str = undefined;
        if (loadFromPath(me.sess.mem_alloc, me.full_path)) |src_bytes|
            src = src_bytes
        else |err| {
            me.notes.errs.load = err;
            me.notes.errs.parse = 0;
            me.clearBuildIssues();
            me.deinitAsts();
            try me.sess.workers.issues_announcer.base.appendJobs(&[_]u64{me.id});
            return true;
        }

        var ast_checknums = [2]u64{ src.len, std.hash.Wyhash.hash(src.len, src) };
        if (me.ast.cur == null or ast_checknums[0] != me.ast.checknums[0] or ast_checknums[1] != me.ast.checknums[1]) {
            const new_ast = std.zig.parse(me.sess.mem_alloc, src) catch |err| switch (err) {
                error.OutOfMemory => return err, // no `try`: in case .parse() returns new errors in the future we'll notice it here
            };
            const parse_ok = (new_ast.errors.len == 0);
            const both_old_asts_were_the_same_ptrs = (me.ast.cur != null and me.ast.good != null and me.ast.cur.? == me.ast.good.?);
            const dispose_good = me.ast.good != null and !both_old_asts_were_the_same_ptrs and parse_ok;
            const dispose_cur = me.ast.cur != null and (!both_old_asts_were_the_same_ptrs or parse_ok);
            if (dispose_good) {
                me.sess.mem_alloc.free(me.ast.good.?.source);
                me.ast.good.?.deinit();
            }
            if (dispose_cur) {
                me.sess.mem_alloc.free(me.ast.cur.?.source);
                me.ast.cur.?.deinit();
            }

            me.ast.cur = new_ast;
            me.notes.errs.parse = new_ast.errors.len;
            if (parse_ok) {
                me.ast.good = new_ast;
                if (me.intel) |*intel|
                    if (intel.src_checknums[0] != ast_checknums[0] or intel.src_checknums[1] != ast_checknums[1]) {
                        intel.deinit();
                        me.intel = null;
                    };
                if (me.intel == null) {
                    me.intel = Intel{
                        .mem = std.heap.ArenaAllocator.init(me.sess.mem_alloc),
                        .src_file = me,
                        .src_checknums = ast_checknums,
                        .src_is_ascii_only = check: {
                            for (src) |byte, bidx| if (byte > 127)
                                break :check false;
                            break :check true;
                        },
                        .node_intels = undefined, // MUST be set directly next (once `mem` arena is settled), right below:
                    };
                    me.intel.?.node_intels = std.AutoHashMap(*const zig_ast.Node, *SrcIntel.NodeIntel).init(&me.intel.?.mem.allocator);
                    // try SrcIntel.ensureNamedDecls(mem_temp, &SrcFileAstCtx{ .src_file = me, .ast = new_ast });
                }
            }
            me.ast.checknums = ast_checknums;
            try me.sess.workers.issues_announcer.base.appendJobs(&[_]u64{me.id});
            return true;
        } else
            me.sess.mem_alloc.free(src);
        return false;
    }

    pub fn ensureDirectImportsInIntel(me: *SrcFile, mem_temp: *std.heap.ArenaAllocator) !bool {
        const lock = me.mutex.acquire();
        defer lock.release();
        if (me.intel) |*intel|
            if (intel.direct_imports == null) {
                intel.direct_imports = try me.gatherDirectImports(&intel.mem.allocator, mem_temp);
                return true;
            };
        return false;
    }

    fn gatherDirectImports(me: *SrcFile, mem: *std.mem.Allocator, mem_temp: *std.heap.ArenaAllocator) ![]Str {
        const my_dir_path = std.fs.path.dirname(me.full_path) orelse ".";
        var direct_imports = std.StringHashMap(void).init(&mem_temp.allocator);
        const ast = me.ast.good orelse unreachable;

        var ctx = try SrcFileAstCtx.init(mem_temp, me, ast);
        defer ctx.deinit();

        var nodes_walk_stack = try std.ArrayList(*zig_ast.Node).initCapacity(&mem_temp.allocator, 256); // good capacity for ~95% of inputs (judging by std lib)
        try nodes_walk_stack.append(&ast.root_node.base);
        while (nodes_walk_stack.len > 0) {
            const cur_node = nodes_walk_stack.swapRemove(0);
            switch (cur_node.id) {
                else => {},
                .BuiltinCall => if (cur_node.cast(zig_ast.Node.BuiltinCall)) |this_bcall| {
                    const name_token = ast.tokens.at(this_bcall.builtin_token);
                    if (this_bcall.params.count() != 1 or !std.mem.eql(u8, "@import", ast.tokenSlicePtr(name_token)))
                        continue;
                    for (try zast.resolve(ctx, this_bcall.params.at(0).*, .{}, null)) |result|
                        switch (result) {
                            else => continue,
                            .lit_str => |str_lit_val| {
                                if (!std.mem.endsWith(u8, str_lit_val, ".zig"))
                                    _ = try direct_imports.put(str_lit_val, {})
                                else {
                                    if (std.fs.path.resolve(&mem_temp.allocator, &[_]Str{ my_dir_path, str_lit_val })) |file_abs_path| {
                                        if (!std.mem.eql(u8, file_abs_path, me.full_path))
                                            _ = try direct_imports.put(file_abs_path, {});
                                    } else |err| switch (err) {
                                        error.OutOfMemory => return err,
                                        else => {},
                                    }
                                }
                            },
                        };
                },
            }
            var i: usize = 0;
            while (cur_node.iterate(i)) |sub_node| : (i += 1)
                try nodes_walk_stack.append(sub_node);
        }
        var ret = try mem.alloc(Str, direct_imports.count());
        var iter = direct_imports.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| : (i += 1)
            ret[i] = try std.mem.dupe(mem, u8, entry.key);
        return ret;
    }

    pub const Intel = struct {
        mem: std.heap.ArenaAllocator,
        src_file: *SrcFile,
        src_checknums: [2]u64,
        src_is_ascii_only: bool,

        direct_imports: ?[]Str = null,
        named_decls: ?zag.Flatree(SrcIntel.NamedDecl) = null,
        node_intels: std.AutoHashMap(*const zig_ast.Node, *SrcIntel.NodeIntel),

        fn deinit(me: *Intel) void {
            me.mem.deinit();
        }
    };

    pub const Note = struct {
        message: Str,
        pos1based_line_and_char: [2]usize,
        related_notes: ?std.ArrayList(Related) = null,

        pub const Related = struct {
            full_file_path: Str,
            message: Str,
            pos1based_line_and_char: [2]usize,
        };

        pub fn equivalentIfIgnoringRelatedNotes(one: Note, two: Note) bool {
            return one.pos1based_line_and_char[0] == two.pos1based_line_and_char[0] and
                one.pos1based_line_and_char[1] == two.pos1based_line_and_char[1] and
                std.mem.eql(u8, one.message, two.message);
        }
    };
};
