usingnamespace @import("./_usingnamespace.zig");

pub const SrcFileAstCtx = struct {
    src_file: *SrcFile,
    ast: *zig_ast.Tree,
    _extra_accumulated: struct {
        ctxs: *std.StringHashMap(*SrcFileAstCtx),
        locks: *std.StringHashMap(std.Mutex.Held),
    },

    pub fn init(mem_temp: *std.heap.ArenaAllocator, src_file: *SrcFile, ast: *zig_ast.Tree) !*SrcFileAstCtx {
        var me = try mem_temp.allocator.create(SrcFileAstCtx);
        me.* = .{
            .src_file = src_file,
            .ast = ast,
            ._extra_accumulated = .{
                .ctxs = try zag.mem.enHeap(&mem_temp.allocator, std.StringHashMap(*SrcFileAstCtx).init(&mem_temp.allocator)),
                .locks = try zag.mem.enHeap(&mem_temp.allocator, std.StringHashMap(std.Mutex.Held).init(&mem_temp.allocator)),
            },
        };
        _ = try me._extra_accumulated.ctxs.put(src_file.full_path, me);
        return me;
    }

    /// won't deinit the actual backing src_file or ast, these are longer-lived
    pub fn deinit(me: *SrcFileAstCtx) void {
        var iter = me._extra_accumulated.locks.iterator();
        while (iter.next()) |entry|
            entry.value.release(); // dont want deinitAndUnlock here, would recurse infinitely as all sub entries share this same _extra_accumulated.locks as this root does
        me._extra_accumulated.locks.deinit();
    }

    pub fn ensureNodeIntel(me: *const SrcFileAstCtx, node: *const zig_ast.Node) !*SrcIntel.NodeIntel {
        if (me.src_file.intel.?.node_intels.get(node)) |entry|
            return entry.value;

        var node_intel = try me.src_file.intel.?.mem.allocator.create(SrcIntel.NodeIntel);
        node_intel.* = .{
            .all_facts = std.AutoHashMap(@TagType(SrcIntel.NodeIntel.Fact), SrcIntel.NodeIntel.Fact).init(&me.src_file.intel.?.mem.allocator),
        };
        _ = try me.src_file.intel.?.node_intels.put(node, node_intel);
        return node_intel;
    }

    pub fn extra(me: *SrcFileAstCtx, src_file_absolute_path: Str) !?*SrcFileAstCtx {
        if (!me._extra_accumulated.ctxs.contains(src_file_absolute_path))
            if (me.session().src_files.getByFullPath(src_file_absolute_path)) |src_file| {
                const lock = src_file.mutex.acquire();
                errdefer lock.release();
                if (src_file.ast.good) |ast| {
                    _ = try me._extra_accumulated.ctxs.put(
                        src_file_absolute_path,
                        try zag.mem.enHeap(me.memTempAlloc(), SrcFileAstCtx{
                            .src_file = src_file,
                            .ast = ast,
                            ._extra_accumulated = me._extra_accumulated,
                        }),
                    );
                    _ = try me._extra_accumulated.locks.put(src_file_absolute_path, lock);
                } else
                    lock.release();
            };
        return me._extra_accumulated.ctxs.getValue(src_file_absolute_path);
    }

    inline fn session(me: *const SrcFileAstCtx) *Session {
        return me.src_file.sess;
    }

    pub inline fn memTempArena(me: *const SrcFileAstCtx) *std.heap.ArenaAllocator {
        return @fieldParentPtr(std.heap.ArenaAllocator, "allocator", me._extra_accumulated.ctxs.allocator);
    }

    pub inline fn memTempAlloc(me: *const SrcFileAstCtx) *std.mem.Allocator {
        return me._extra_accumulated.ctxs.allocator;
    }
};

pub const SrcIntel = struct {
    sess: *Session,

    pub var convertPosInfoToCustom: fn (*std.heap.ArenaAllocator, Str, bool, [2]usize, SrcIntel.Location.PosInfoKind) anyerror![]usize = defaultConvertPosInfoToCustom;
    pub var convertPosInfoFromCustom: fn (*std.heap.ArenaAllocator, Str, bool, []usize) anyerror!?usize = defaultConvertPosInfoFromCustom;

    fn defaultConvertPosInfoFromCustom(mem: *std.heap.ArenaAllocator, src: Str, is_ascii_only: bool, pos_info: []usize) !?usize {
        return error.MustBeProvidedByLibUser;
    }
    fn defaultConvertPosInfoToCustom(mem: *std.heap.ArenaAllocator, src: Str, is_ascii_only: bool, pos: [2]usize, from_kind: SrcIntel.Location.PosInfoKind) ![]usize {
        return error.MustBeProvidedByLibUser;
    }

    pub fn deinit(me: *SrcIntel) void {}

    fn srcFileAstCtx(me: *SrcIntel, mem_temp: *std.heap.ArenaAllocator, src_file_absolute_path: Str) !?zag.Locked(*SrcFileAstCtx) {
        const src_file = me.sess.src_files.getByFullPath(src_file_absolute_path) orelse return null;
        const src_file_lock = src_file.mutex.acquire();
        if (src_file.ast.good) |ast|
            if (src_file.intel != null)
                return zag.Locked(*SrcFileAstCtx){
                    .lock = src_file_lock,
                    .item = try SrcFileAstCtx.init(mem_temp, src_file, ast),
                };
        src_file_lock.release();
        return null;
    }

    fn namedDeclInit(ctx: *const SrcFileAstCtx, into: *zag.Flatree(NamedDecl), node: *zig_ast.Node, cur_parent_decl: ?usize, tok_first: *const std.zig.Token, tok_last: *const std.zig.Token, tok_name_or_kind: *const std.zig.Token, kind: NamedDecl.Kind) !usize {
        var decl = NamedDecl{ .node = node, .kind = kind, .pos = .{ .full = .{ .start = tok_first.start, .end = tok_last.end } } };
        decl.pos.name = .{ .start = tok_name_or_kind.start, .end = tok_name_or_kind.end };
        const idx = try into.add(decl, cur_parent_decl);
        const node_intel = try ctx.ensureNodeIntel(node);
        try node_intel.takeNoteOf(.{ .named_decl = idx });
        return idx;
    }

    pub fn ensureNamedDecls(ctx: *const SrcFileAstCtx) !void {
        const src_file = ctx.src_file;
        if (src_file.intel.?.named_decls == null) {
            const ast = ctx.ast;
            var decls = try zag.Flatree(NamedDecl).init(&src_file.intel.?.mem.allocator, 256);
            const StackItem = struct {
                parent_decl: ?usize,
                node: *zig_ast.Node,
            };

            var nodes_walk_stack = try std.ArrayList(StackItem).initCapacity(ctx.memTempAlloc(), 256); // good capacity for ~95% of inputs (judging by std lib)
            try nodes_walk_stack.append(.{ .parent_decl = null, .node = &ast.root_node.base });
            while (nodes_walk_stack.len > 0) {
                const cur = nodes_walk_stack.swapRemove(0);
                var next_parent = cur.parent_decl;
                switch (cur.node.id) {
                    else => {},

                    .FnProto => if (cur.node.cast(zig_ast.Node.FnProto)) |this_fn|
                        if (this_fn.name_token) |name_token_index|
                            if (this_fn.body_node) |body_node| {
                                const name_token = ast.tokens.at(name_token_index);
                                next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_fn.firstToken()), ast.tokens.at(this_fn.lastToken()), name_token, .{
                                    .Fn = .{
                                        .returns_type = switch (this_fn.return_type) {
                                            else => false,
                                            .Explicit => |node| if (node.cast(zig_ast.Node.Identifier)) |ident|
                                                std.mem.eql(u8, "type", ast.tokenSlice(ident.token))
                                            else
                                                false,
                                        },
                                    },
                                });
                                var this_decl = decls.get(next_parent.?);
                                // this_decl.pos.brief = .{ .start = ast.tokens.at(this_fn.firstToken()).start, .end = ast.tokens.at(body_node.firstToken()).start };
                                this_decl.pos.brief = .{ .start = this_decl.pos.name.?.end, .end = ast.tokens.at(body_node.firstToken()).start };
                            },

                    .TestDecl => if (cur.node.cast(zig_ast.Node.TestDecl)) |this_test|
                        if (this_test.name.cast(zig_ast.Node.StringLiteral)) |str_lit| {
                            const name_token = ast.tokens.at(str_lit.token);
                            next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_test.firstToken()), ast.tokens.at(this_test.lastToken()), name_token, .{ .Test = {} });
                            var this_decl = decls.get(next_parent.?);
                            // this_decl.pos.brief = .{ .start = ast.tokens.at(this_test.firstToken()).start, .end = ast.tokens.at(this_test.body_node.firstToken()).start };
                            this_decl.pos.brief = .{ .start = ast.tokens.at(this_test.firstToken()).start, .end = this_decl.pos.name.?.start };
                        },

                    .Block => if (cur.node.cast(zig_ast.Node.Block)) |this_block|
                        if (this_block.label) |name_token_index| {
                            const name_token = ast.tokens.at(name_token_index);
                            next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_block.firstToken()), ast.tokens.at(this_block.lastToken()), name_token, .{ .Block = {} });
                            var this_decl = decls.get(next_parent.?);
                            this_decl.pos.brief = .{ .start = ast.tokens.at(this_block.lbrace).start, .end = ast.tokens.at(this_block.rbrace).end };
                        },

                    .ParamDecl => if (cur.node.cast(zig_ast.Node.ParamDecl)) |this_param|
                        if (this_param.name_token) |name_token_index| {
                            const name_token = ast.tokens.at(name_token_index);
                            next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_param.firstToken()), ast.tokens.at(this_param.lastToken()), name_token, .{ .FnArg = {} });
                            var this_decl = decls.get(next_parent.?);
                            this_decl.pos.brief = .{ .start = ast.tokens.at(this_param.type_node.firstToken()).start, .end = ast.tokens.at(this_param.type_node.lastToken()).end };
                        },

                    .VarDecl => if (cur.node.cast(zig_ast.Node.VarDecl)) |this_var| {
                        const name_token = ast.tokens.at(this_var.name_token);
                        const mut_token = ast.tokenSlice(this_var.mut_token);
                        const kind: NamedDecl.Kind = if (std.mem.eql(u8, "const", mut_token))
                            .{ .IdentConst = {} }
                        else if (std.mem.eql(u8, "var", mut_token))
                            .{ .IdentVar = {} }
                        else
                            @panic(mut_token);
                        next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_var.firstToken()), ast.tokens.at(this_var.lastToken()), name_token, kind);
                        var this_decl = decls.get(next_parent.?);
                        if (this_var.type_node) |type_node|
                            this_decl.pos.brief = .{ .start = ast.tokens.at(type_node.firstToken()).start, .end = ast.tokens.at(type_node.lastToken()).end }
                        else if (this_var.init_node) |init_node| {
                            if (this_var.eq_token) |eq_token|
                                this_decl.pos.brief = .{ .start = ast.tokens.at(eq_token).start, .end = ast.tokens.at(init_node.lastToken()).end }
                            else
                                this_decl.pos.brief = .{ .start = ast.tokens.at(init_node.firstToken()).start, .end = ast.tokens.at(init_node.lastToken()).end };
                        }
                    },

                    .ContainerDecl => if (cur.node.cast(zig_ast.Node.ContainerDecl)) |this_cont| {
                        const kind_token = ast.tokens.at(this_cont.kind_token);
                        const kind: NamedDecl.Kind = from_kind: {
                            const kind_tok_src = ast.tokenSlicePtr(kind_token);
                            if (std.mem.eql(u8, kind_tok_src, "struct"))
                                break :from_kind .{ .Struct = {} };
                            if (std.mem.eql(u8, kind_tok_src, "union"))
                                break :from_kind .{ .Union = {} };
                            if (std.mem.eql(u8, kind_tok_src, "enum"))
                                break :from_kind .{ .Enum = {} };
                            @panic(kind_tok_src);
                        };
                        next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_cont.firstToken()), ast.tokens.at(this_cont.lastToken()), kind_token, kind);
                        var this_decl = decls.get(next_parent.?);
                        this_decl.pos.brief = .{ .start = ast.tokens.at(this_cont.lbrace_token).start, .end = ast.tokens.at(this_cont.rbrace_token).end };
                    },

                    .ContainerField => if (cur.node.cast(zig_ast.Node.ContainerField)) |this_field| {
                        const name_token = ast.tokens.at(this_field.name_token);
                        const is_struct_field = if (next_parent) |np| (decls.get(np).kind == .Struct) else false;
                        next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_field.firstToken()), ast.tokens.at(this_field.lastToken()), name_token, .{ .Field = .{ .is_struct_field = is_struct_field } });
                        var this_decl = decls.get(next_parent.?);
                        if (this_field.type_expr) |type_expr| {
                            if (this_field.value_expr) |value_expr|
                                this_decl.pos.brief = .{ .start = ast.tokens.at(type_expr.firstToken()).start, .end = ast.tokens.at(value_expr.lastToken()).end }
                            else
                                this_decl.pos.brief = .{ .start = ast.tokens.at(type_expr.firstToken()).start, .end = ast.tokens.at(type_expr.lastToken()).end };
                        } else if (this_field.value_expr) |value_expr|
                            this_decl.pos.brief = .{ .start = ast.tokens.at(value_expr.firstToken()).start, .end = ast.tokens.at(value_expr.lastToken()).end };
                    },

                    .FieldInitializer => if (cur.node.cast(zig_ast.Node.FieldInitializer)) |this_init| {
                        const name_token = ast.tokens.at(this_init.name_token);
                        next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_init.firstToken()), ast.tokens.at(this_init.lastToken()), name_token, .{ .Init = {} });
                        var this_decl = decls.get(next_parent.?);
                        this_decl.pos.brief = .{ .start = ast.tokens.at(this_init.expr.firstToken()).start, .end = ast.tokens.at(this_init.expr.lastToken()).end };
                        this_decl.pos.name.?.start = ast.tokens.at(this_init.period_token).start;
                        this_decl.pos.name.?.end = ast.tokens.at(1 + this_init.name_token).end;
                    },

                    .ErrorTag => if (cur.node.cast(zig_ast.Node.ErrorTag)) |this_errtag| {
                        const name_token = ast.tokens.at(this_errtag.name_token);
                        next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_errtag.firstToken()), ast.tokens.at(this_errtag.lastToken()), name_token, .{ .Field = .{ .is_struct_field = false } });
                        var this_decl = decls.get(next_parent.?);
                        if (this_errtag.doc_comments) |doc_comments|
                            this_decl.pos.brief = .{ .start = ast.tokens.at(doc_comments.firstToken()).start, .end = ast.tokens.at(doc_comments.lastToken()).end };
                    },

                    .Use => if (cur.node.cast(zig_ast.Node.Use)) |this_use| {
                        const name_token = ast.tokens.at(this_use.use_token);
                        next_parent = try namedDeclInit(ctx, &decls, cur.node, cur.parent_decl, ast.tokens.at(this_use.firstToken()), ast.tokens.at(this_use.lastToken()), name_token, .{ .Using = {} });
                        var this_decl = decls.get(next_parent.?);
                        this_decl.pos.brief = .{ .start = ast.tokens.at(this_use.expr.firstToken()).start, .end = ast.tokens.at(this_use.lastToken()).end };
                    },

                    .Payload => if (cur.node.cast(zig_ast.Node.Payload)) |this_payload_err| {
                        const node_ident = this_payload_err.error_symbol.cast(zig_ast.Node.Identifier).?;
                        const name_token = ast.tokens.at(node_ident.token);
                        next_parent = try namedDeclInit(ctx, &decls, this_payload_err.error_symbol, cur.parent_decl, ast.tokens.at(node_ident.firstToken()), ast.tokens.at(node_ident.lastToken()), name_token, .{ .Payload = .{ .kind = .err } });
                        // var this_decl = decls.get(next_parent.?);
                    },

                    .PointerPayload => if (cur.node.cast(zig_ast.Node.PointerPayload)) |this_payload_ptr| {
                        const node_ident = this_payload_ptr.value_symbol.cast(zig_ast.Node.Identifier).?;
                        const name_token = ast.tokens.at(node_ident.token);
                        next_parent = try namedDeclInit(ctx, &decls, this_payload_ptr.value_symbol, cur.parent_decl, ast.tokens.at(node_ident.firstToken()), ast.tokens.at(node_ident.lastToken()), name_token, .{ .Payload = .{ .kind = .ptr } });
                        // var this_decl = decls.get(next_parent.?);
                    },

                    .PointerIndexPayload => if (cur.node.cast(zig_ast.Node.PointerIndexPayload)) |this_payload_idx| {
                        var node_ident = this_payload_idx.value_symbol.cast(zig_ast.Node.Identifier).?;
                        var name_token = ast.tokens.at(node_ident.token);
                        next_parent = try namedDeclInit(ctx, &decls, this_payload_idx.value_symbol, cur.parent_decl, ast.tokens.at(node_ident.firstToken()), ast.tokens.at(node_ident.lastToken()), name_token, .{ .Payload = .{ .kind = .ptr } });
                        // var this_decl = decls.get(next_parent.?);
                        if (this_payload_idx.index_symbol) |index_symbol| {
                            node_ident = index_symbol.cast(zig_ast.Node.Identifier).?;
                            name_token = ast.tokens.at(node_ident.token);
                            _ = try namedDeclInit(ctx, &decls, index_symbol, cur.parent_decl, ast.tokens.at(node_ident.firstToken()), ast.tokens.at(node_ident.lastToken()), name_token, .{ .Payload = .{ .kind = .idx } });
                        }
                    },
                }

                var i: usize = 0;
                while (cur.node.iterate(i)) |sub_node| : (i += 1)
                    try nodes_walk_stack.append(.{ .node = sub_node, .parent_decl = next_parent });
            }
            decls.all_nodes.shrink(decls.all_nodes.len);
            src_file.intel.?.named_decls = decls;
        }
    }

    pub fn withNamedDeclsEnsured(me: *SrcIntel, mem_temp: *std.heap.ArenaAllocator, src_file_absolute_path: Str) !?zag.Locked(*SrcFileAstCtx) {
        const locked = (try me.srcFileAstCtx(mem_temp, src_file_absolute_path)) orelse return null;
        try ensureNamedDecls(locked.item);
        return locked;
    }

    pub const Resolved = struct {
        the: *SrcFileAstCtx,
        node: *zig_ast.Node,
        resolveds: []const zast.Resolved,

        pub fn deinit(me: *Resolved) void {
            me.the.deinit();
        }
    };

    pub fn resolve(me: *SrcIntel, mem_temp: *std.heap.ArenaAllocator, location: Location) !?zag.Locked(Resolved) {
        var locked = (try me.srcFileAstCtx(mem_temp, location.full_path)) orelse return null;
        errdefer locked.deinitAndUnlock();

        const byte_pos = (try convertPosInfoFromCustom(mem_temp, locked.item.ast.source, locked.item.src_file.intel.?.src_is_ascii_only, location.pos_info)) orelse {
            locked.deinitAndUnlock();
            return null;
        };
        const node_path = (try zast.pathToNode(locked.item, .{ .byte_position = byte_pos })) orelse {
            locked.deinitAndUnlock();
            return null;
        };
        return zag.Locked(Resolved){
            .lock = locked.lock,
            .item = .{
                .the = locked.item,
                .node = node_path[node_path.len - 1],
                .resolveds = try zast.resolve(locked.item, node_path[node_path.len - 1], .{ .resolve_loc_refs_to_final_values = false }, node_path),
            },
        };
    }

    pub fn lookup(me: *SrcIntel, mem_temp: *std.heap.ArenaAllocator, kind: Lookup, location: Location) ![]Location {
        const ret_nil = &[_]Location{};
        var locked = (try me.srcFileAstCtx(mem_temp, location.full_path)) orelse return ret_nil;
        defer locked.deinitAndUnlock();

        const node_path = (try zast.pathToNode(locked.item, .{
            .byte_position = (try convertPosInfoFromCustom(mem_temp, locked.
                item.ast.source, locked.item.src_file.intel.?.src_is_ascii_only, location.pos_info)) orelse return ret_nil,
        })) orelse return ret_nil;
        switch (kind) {
            .Definitions => return me.lookupDefinitions(locked.item, node_path),
            else => return error.ToDo,
        }
    }

    fn lookupDefinitions(me: *SrcIntel, ctx: *SrcFileAstCtx, node_path: []*zig_ast.Node) ![]Location {
        var ret_locs = try std.ArrayList(Location).initCapacity(ctx.memTempAlloc(), 2);
        const node = node_path[node_path.len - 1];

        if (node.cast(zig_ast.Node.BuiltinCall)) |this_bcall| builtin_call: {
            const name = std.mem.trimLeft(u8, ctx.ast.tokenSlicePtr(ctx.ast.tokens.at(this_bcall.builtin_token)), "@");
            try ret_locs.append(.{
                .full_path = me.sess.zig_install.langrefHtmlFilePathGuess() orelse break :builtin_call,
                .pos_info = (try me.sess.zig_install.langrefHtmlFileSrcRange(ctx.memTempArena(), name)) orelse break :builtin_call,
            });
        } else {
            try ensureNamedDecls(ctx);
            for (try zast.resolve(ctx, node, .{ .resolve_loc_refs_to_final_values = false }, node_path)) |resolved|
                switch (resolved) {
                    else => {},
                    .loc_ref => |*loc_ref| {
                        var tok_start = loc_ref.node.firstToken();
                        var tok_end = loc_ref.node.lastToken();
                        if (loc_ref.ctx.src_file == ctx.src_file and zast.nodeEncloses(loc_ref.ctx.ast, loc_ref.node, node))
                            tok_end = zast.nodeFirstSubNode(loc_ref.node).?.firstToken();
                        try ret_locs.append(.{
                            .full_path = loc_ref.ctx.src_file.full_path,
                            .pos_info = try convertPosInfoToCustom(loc_ref.ctx.memTempArena(), loc_ref.ctx.ast.source, loc_ref.ctx.src_file.intel.?.src_is_ascii_only, [2]usize{
                                loc_ref.ctx.ast.tokens.at(tok_start).start,
                                loc_ref.ctx.ast.tokens.at(tok_end).end,
                            }, .byte_offsets_0_based_range),
                        });
                    },
                };
        }
        return ret_locs.items[0..ret_locs.len];
    }

    pub const Lookup = union(enum) {
        Definitions,
        References,
        TypeDefinitions,
    };

    pub const NodeIntel = struct {
        all_facts: std.AutoHashMap(@TagType(Fact), Fact),

        pub fn takeNoteOf(me: *NodeIntel, fact: Fact) !void {
            try me.all_facts.putNoClobber(std.meta.activeTag(fact), fact);
        }

        pub const Fact = union(enum) {
            named_decl: usize,
        };
    };

    pub const NamedDecl = struct {
        node: *zig_ast.Node,
        kind: Kind,
        pos: struct {
            full: zag.Range(usize),
            name: ?zag.Range(usize) = null,
            brief: ?zag.Range(usize) = null,
        },

        pub fn isContainer(me: *const NamedDecl) bool {
            return switch (me.kind) {
                else => false,
                .Union, .Enum, .Struct => true,
            };
        }

        pub const Kind = union(enum) {
            Test: void,
            Fn: struct { returns_type: bool },
            Block: void,
            FnArg: void,
            Enum: void,
            Union: void,
            Struct: void,
            Field: struct { is_struct_field: bool },
            IdentVar: void,
            IdentConst: void,
            Init: void,
            Using: void,
            Payload: struct { kind: enum { err, ptr, idx } },
        };
    };

    pub const Location = struct {
        full_path: Str,
        pos_info: []usize,

        pub const PosInfoKind = enum {
            byte_offsets_0_based_range,
            line_and_col_1_based_pos,
        };
    };
};
