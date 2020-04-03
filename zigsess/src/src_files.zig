usingnamespace @import("./_usingnamespace.zig");

pub const SrcFiles = struct {
    sess: *Session,
    mutex: std.Mutex = std.Mutex.init(),
    files: std.AutoHashMap(u64, *SrcFile),
    issues: std.StringHashMap([]Issue),
    build_zig_dir_paths: std.StringHashMap(void),

    pub var onIssuesRefreshed: fn (*std.heap.ArenaAllocator, std.StringHashMap([]Issue)) anyerror!void = defaultOnIssuesRefreshed;
    pub var onBuildRuns: ?fn (OnBuildRuns) void = null;
    pub const OnBuildRuns = union(enum) { begun: void, ended: void, cur_build_dir: Str };

    fn defaultOnIssuesRefreshed(mem: *std.heap.ArenaAllocator, fresh_issues: std.StringHashMap([]Issue)) error{}!void {}

    pub fn deinit(me: *SrcFiles) void {
        const lock = me.mutex.acquire();
        defer lock.release();

        me.build_zig_dir_paths.deinit();

        var iter_issues = me.issues.iterator();
        while (iter_issues.next()) |path_and_issues| {
            for (path_and_issues.value) |*issue|
                issue.deinitFrom(me.sess.mem_alloc);
            me.sess.mem_alloc.free(path_and_issues.value);
        }
        me.issues.deinit();

        var iter_files = me.files.iterator();
        while (iter_files.next()) |src_file_entry|
            src_file_entry.value.deinit();
        me.files.deinit();
    }

    inline fn panicIfCollision(src_file_path_want: Str, src_file_path_have: Str) void {
        if (!std.mem.eql(u8, src_file_path_want, src_file_path_have))
            std.debug.panic(
                \\unexpected hash collision between {s} and {s}
                \\please report to github.com/meta-leap/zigsess thanks!
            , .{ src_file_path_want, src_file_path_have });
    }

    pub fn allCurrentlyTrackedSrcFileAbsPaths(me: *SrcFiles, mem: *std.mem.Allocator) ![]Str {
        var i: usize = 0;
        const lock = me.mutex.acquire();
        defer lock.release();
        var ret = try mem.alloc(Str, me.files.count());
        var iter = me.files.iterator();
        while (iter.next()) |src_file_entry| : (i += 1)
            ret[i] = src_file_entry.value.full_path;
        return ret;
    }

    pub fn allCurrentlyTrackedSrcFiles(me: *SrcFiles, mem: *std.mem.Allocator) ![]*SrcFile {
        var i: usize = 0;
        const lock = me.mutex.acquire();
        defer lock.release();
        var ret = try mem.alloc(*SrcFile, me.files.count());
        var iter = me.files.iterator();
        while (iter.next()) |src_file_entry| : (i += 1)
            ret[i] = src_file_entry.value;
        return ret;
    }

    inline fn getById(me: *SrcFiles, src_file_id: u64) ?*SrcFile {
        const lock = me.mutex.acquire();
        defer lock.release();
        return me.files.getValue(src_file_id);
    }

    pub fn getByIds(me: *SrcFiles, mem: *std.mem.Allocator, src_file_ids: []const u64) ![]?*SrcFile {
        var ret = try mem.alloc(?*SrcFile, src_file_ids.len);
        const lock = me.mutex.acquire();
        defer lock.release();
        for (src_file_ids) |src_file_id, i|
            ret[i] = me.files.getValue(src_file_id);
        return ret;
    }

    pub fn getByFullPath(me: *SrcFiles, src_file_absolute_path: Str) ?*SrcFile {
        var ret = me.getById(SrcFile.id(src_file_absolute_path));
        if (ret) |it|
            panicIfCollision(src_file_absolute_path, it.full_path);
        return ret;
    }

    pub fn ensureFilesTracked(me: *SrcFiles, mem_temp: *std.heap.ArenaAllocator, src_file_absolute_paths: []const EnsureTracked) !void {
        var any_new_files = false;
        var reload_src_file_ids = try std.ArrayList(u64).initCapacity(&mem_temp.allocator, src_file_absolute_paths.len);
        const lock = me.mutex.acquire();
        defer lock.release();
        for (src_file_absolute_paths) |intent| {
            var mark_for_reload = intent.force_reload;
            const src_file_id = SrcFile.id(intent.absolute_path);
            if (me.files.get(src_file_id)) |existing|
                panicIfCollision(intent.absolute_path, existing.value.full_path)
            else {
                mark_for_reload = true;
                any_new_files = true;
                var src_file = try me.sess.mem_alloc.create(SrcFile);
                src_file.* = SrcFile{
                    .ast = .{},
                    .sess = me.sess,
                    .id = src_file_id,
                    .full_path = try std.mem.dupe(me.sess.mem_alloc, u8, intent.absolute_path),
                    .notes = .{ .errs = .{ .build = std.ArrayList(SrcFile.Note).init(me.sess.mem_alloc) } },
                    .direct_importers = std.StringHashMap(void).init(me.sess.mem_alloc),
                };
                _ = try me.files.put(src_file_id, src_file);
                if (std.mem.eql(u8, "build.zig", std.fs.path.basename(src_file.full_path))) {
                    if (std.fs.path.dirname(src_file.full_path)) |build_zig_dir_path|
                        _ = try me.build_zig_dir_paths.put(build_zig_dir_path, {});
                }
            }
            if (mark_for_reload)
                try reload_src_file_ids.append(src_file_id);
        }

        if (reload_src_file_ids.len != 0) {
            me.sess.workers.src_files_refresh_imports.base.cancelPendingEnqueuedJobs(reload_src_file_ids.toSlice());
            try me.sess.workers.src_files_reloader.base.appendJobs(reload_src_file_ids.toSlice());
        }

        if (any_new_files) {
            var build_dir_candidates = try std.ArrayList(Str).initCapacity(&mem_temp.allocator, 4);
            var iter_files = me.files.iterator();
            while (iter_files.next()) |src_file| {
                build_dir_candidates.len = 0;
                const src_file_path = src_file.value.full_path;

                var iter_all_build_dirs = me.build_zig_dir_paths.iterator();
                while (iter_all_build_dirs.next()) |bd| {
                    if (src_file_path.len > bd.key.len and
                        src_file_path[bd.key.len] == std.fs.path.sep and
                        std.mem.startsWith(u8, src_file_path, bd.key))
                        try build_dir_candidates.append(bd.key);
                }

                if (build_dir_candidates.len != 0) {
                    var idx: usize = 0;
                    var max = build_dir_candidates.items[0].len;
                    for (build_dir_candidates.items[0..build_dir_candidates.len]) |bdc, i|
                        if (bdc.len > max) {
                            idx = i;
                            max = bdc.len;
                        };

                    const lock_file = src_file.value.mutex.acquire();
                    defer lock_file.release();
                    src_file.value.build_zig_dir_path = build_dir_candidates.items[idx];
                }
            }
        }
    }

    fn reGatherIssues(me: *SrcFiles, mem_temp: *std.heap.ArenaAllocator, src_file_ids: []const u64) !void {
        var fresh_issues = std.StringHashMap([]Issue).init(&mem_temp.allocator);
        const src_files = try me.getByIds(&mem_temp.allocator, src_file_ids);
        for (src_files) |maybe_src_file| {
            const src_file = maybe_src_file orelse continue;
            var file_issues = std.ArrayList(Issue).init(&mem_temp.allocator);
            {
                const lock = src_file.mutex.acquire();
                defer lock.release();

                for (src_file.notes.errs.build.items[0..src_file.notes.errs.build.len]) |*build_issue| {
                    const idx = file_issues.len;
                    try file_issues.append(.{
                        .scope = .zig_build,
                        .message = try std.mem.dupe(&mem_temp.allocator, u8, build_issue.message),
                        .pos_info = try SrcIntel.convertPosInfoToCustom(mem_temp, "", true, build_issue.pos1based_line_and_char, .line_and_col_1_based_pos),
                    });
                    if (build_issue.related_notes) |*related_notes| {
                        const this_issue = &file_issues.items[idx];
                        this_issue.relateds = try mem_temp.allocator.alloc(Issue.RelatedNote, related_notes.len);
                        for (this_issue.relateds) |_, i|
                            this_issue.relateds[i] = .{
                                .message = try std.mem.dupe(&mem_temp.allocator, u8, related_notes.items[i].message),
                                .location = .{
                                    .full_path = try std.mem.dupe(&mem_temp.allocator, u8, related_notes.items[i].full_file_path),
                                    .pos_info = try SrcIntel.convertPosInfoToCustom(mem_temp, "", true, related_notes.items[i].pos1based_line_and_char, .line_and_col_1_based_pos),
                                },
                            };
                    }
                }

                if (src_file.notes.errs.load) |load_err| switch (load_err) {
                    error.FileNotFound => {},
                    else => try file_issues.append(.{ .scope = .load, .message = @errorName(load_err) }),
                };

                if (src_file.ast.cur) |ast_cur|
                    if (ast_cur.errors.count() != 0) {
                        var iter_errs = ast_cur.errors.iterator(0);
                        while (iter_errs.next()) |err| {
                            var out = std.io.SliceOutStream.init(try mem_temp.allocator.alloc(u8, 256));
                            try err.render(&ast_cur.tokens, &out.stream);
                            const err_tok = ast_cur.tokens.at(err.loc());
                            try file_issues.append(.{
                                .scope = .parse,
                                .message = out.getWritten(),
                                .pos_info = try SrcIntel.convertPosInfoToCustom(mem_temp, ast_cur.source, false, [2]usize{ err_tok.start, err_tok.end }, .byte_offsets_0_based_range),
                            });
                        }
                    };
            }
            const is_fresh: bool = if (me.issues.getValue(src_file.full_path)) |issues|
                !zag.mem.eqlUnordered(Issue, issues, file_issues.toSlice())
            else
                true; // would feel cleverer to (file_issues.len != 0) instead, but this way is more robust wrt current LSP client behaviors
            if (is_fresh)
                _ = try fresh_issues.put(src_file.full_path, file_issues.toSlice());
        }

        if (fresh_issues.count() != 0) {
            try onIssuesRefreshed(mem_temp, fresh_issues);
            const lock = me.mutex.acquire();
            defer lock.release();
            var iter_fresh = fresh_issues.iterator();
            while (iter_fresh.next()) |path_and_issues| if (try me.issues.put(
                path_and_issues.key,
                try zag.mem.fullDeepCopyTo(me.sess.mem_alloc, path_and_issues.value),
            )) |prior_path_and_issues| {
                for (prior_path_and_issues.value) |*issue|
                    issue.deinitFrom(me.sess.mem_alloc);
                me.sess.mem_alloc.free(prior_path_and_issues.value);
            };
        }
    }

    pub const EnsureTracked = struct {
        absolute_path: Str = "",
        force_reload: bool = false,
        is_dir: bool = false,
    };
    pub const Issue = struct {
        message: Str,
        pos_info: []usize = &[_]usize{},
        scope: enum {
            load,
            parse,
            zig_build,
        },
        relateds: []RelatedNote = &[_]RelatedNote{},

        fn deinitFrom(me: *Issue, mem: *std.mem.Allocator) void {
            mem.free(me.message);
            mem.free(me.pos_info);
            for (me.relateds) |*related| {
                mem.free(related.message);
                mem.free(related.location.full_path);
                mem.free(related.location.pos_info);
            }
            mem.free(me.relateds);
        }

        pub const RelatedNote = struct {
            message: Str,
            location: SrcIntel.Location,
        };
    };
};
