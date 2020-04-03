usingnamespace @import("./_usingnamespace.zig");

pub const zast = struct {
    fn parentDotExpr(mem_temp: *std.heap.ArenaAllocator, node_path: []*zig_ast.Node, closest: bool) ?*zig_ast.Node.InfixOp {
        var ret: ?*zig_ast.Node.InfixOp = null;
        var i: usize = node_path.len - 2;
        while (i > 0) : (i -= 1) {
            if (node_path[i].cast(zig_ast.Node.InfixOp)) |infix_op_node| {
                if (infix_op_node.op != .Period) break else {
                    ret = infix_op_node;
                    if (closest)
                        break;
                }
            } else break;
        }
        return ret;
    }

    fn nestedInfixOpLeftMostOperand(node: *zig_ast.Node.InfixOp) *zig_ast.Node {
        var infix_op_node: *zig_ast.Node.InfixOp = node;
        while (infix_op_node.lhs.id == .InfixOp)
            infix_op_node = infix_op_node.lhs.cast(zig_ast.Node.InfixOp).?;
        return infix_op_node.lhs;
    }

    pub fn nodeEncloses(ast: *zig_ast.Tree, outer_node: *zig_ast.Node, inner_node: *zig_ast.Node) bool {
        return ast.tokens.at(outer_node.firstToken()).start <= ast.tokens.at(inner_node.firstToken()).start and
            ast.tokens.at(outer_node.lastToken()).end >= ast.tokens.at(inner_node.lastToken()).end;
    }

    pub fn nodeFirstSubNode(node: *zig_ast.Node) ?*zig_ast.Node {
        return node.iterate(0);
    }

    pub fn nodeDocComments(mem_temp: *std.heap.ArenaAllocator, ast: *zig_ast.Tree, actual_node: *zig_ast.Node) !?[]const Str {
        const node = unParensed(actual_node);
        inline for (@typeInfo(zig_ast.Node.Id).Enum.fields) |*field| {
            if (node.id == @field(zig_ast.Node.Id, field.name)) {
                const T = @field(zig_ast.Node, field.name);
                if (comptime std.meta.fieldIndex(T, "doc_comments")) |field_idx| {
                    if (@fieldParentPtr(T, "base", node).doc_comments) |doc_comments| {
                        var ret = try std.ArrayList(Str).initCapacity(&mem_temp.allocator, doc_comments.lines.count());
                        var iter = doc_comments.lines.iterator(0);
                        while (iter.next()) |tok_idx|
                            try ret.append(ast.source[ast.tokens.at(tok_idx.*).start..ast.tokens.at(tok_idx.*).end][3..]);
                        return ret.toSliceConst();
                    }
                }
            }
        }
        return null;
    }

    fn nameFromToken(ast: *zig_ast.Tree, node: *zig_ast.Node) ?Str {
        switch (node.id) {
            else => {},
            .ContainerField => if (node.cast(zig_ast.Node.ContainerField)) |it| return ast.tokenSlice(it.name_token),
            .FnProto => if (node.cast(zig_ast.Node.FnProto)) |it| if (it.name_token) |name_token| return ast.tokenSlice(name_token),
            .Block => if (node.cast(zig_ast.Node.Block)) |it| if (it.label) |label| return ast.tokenSlice(label),
            .ParamDecl => if (node.cast(zig_ast.Node.ParamDecl)) |it| if (it.name_token) |name_token| return ast.tokenSlice(name_token),
            .VarDecl => if (node.cast(zig_ast.Node.VarDecl)) |it| return ast.tokenSlice(it.name_token),
            .FieldInitializer => if (node.cast(zig_ast.Node.FieldInitializer)) |it| return ast.tokenSlice(it.name_token),
            .ErrorTag => if (node.cast(zig_ast.Node.ErrorTag)) |it| return ast.tokenSlice(it.name_token),

            .GroupedExpression => if (node.cast(zig_ast.Node.GroupedExpression)) |it| return nameFromToken(ast, it.expr),
            .Use => if (node.cast(zig_ast.Node.Use)) |it| return nameFromToken(ast, it.expr),
            .Defer => if (node.cast(zig_ast.Node.Defer)) |it| return nameFromToken(ast, it.expr),
            .Payload => if (node.cast(zig_ast.Node.Payload)) |it| return nameFromToken(ast, it.error_symbol),
            .PointerPayload => if (node.cast(zig_ast.Node.PointerPayload)) |it| return nameFromToken(ast, it.value_symbol),
            .PointerIndexPayload => if (node.cast(zig_ast.Node.PointerIndexPayload)) |it| return nameFromToken(ast, it.value_symbol),
            .Comptime => if (node.cast(zig_ast.Node.Comptime)) |it| return nameFromToken(ast, it.expr),
        }
        return null;
    }

    pub fn unParensed(node: *zig_ast.Node) *zig_ast.Node {
        var ret = node;
        while (ret.id == .GroupedExpression)
            ret = ret.cast(zig_ast.Node.GroupedExpression).?.expr;
        return ret;
    }

    pub fn pathToNode(ctx: *const SrcFileAstCtx, to: union(enum) {
        byte_position: usize,
        node: *zig_ast.Node,
    }) !?[]*zig_ast.Node {
        var node_path = try std.ArrayList(*zig_ast.Node).initCapacity(ctx.memTempAlloc(), 8);
        var byte_offset: usize = switch (to) {
            .byte_position => |byte_pos| byte_pos,
            .node => |node| ctx.ast.tokens.at(node.firstToken()).start,
        };

        try node_path.append(&ctx.ast.root_node.base);
        var next_node_found = true;
        _ = pathToNode;
        while (next_node_found) {
            next_node_found = false;
            const cur_node = node_path.items[node_path.len - 1];
            // std.debug.warn("cur-node: {}\t{}\n", .{ node_path.len, cur_node.id });
            var i: usize = 0;
            while (cur_node.iterate(i)) |sub_node| : (i += 1) {
                if (byte_offset >= ctx.ast.tokens.at(sub_node.firstToken()).start and
                    byte_offset < ctx.ast.tokens.at(sub_node.lastToken()).end)
                {
                    next_node_found = true;
                    try node_path.append(sub_node);
                }
            }
        }

        node_path.shrink(node_path.len);
        _ = try ctx.ensureNodeIntel(node_path.items[node_path.len - 1]);
        return if (node_path.len == 1) null else node_path.items[0..node_path.len];
    }

    pub fn resolve(ctx: *SrcFileAstCtx, node: *zig_ast.Node, opts: Resolving, maybe_path_to_node: ?[]*zig_ast.Node) error{OutOfMemory}![]const Resolved {
        var ret = try std.ArrayList(Resolved).initCapacity(ctx.memTempAlloc(), 1);

        switch (node.id) {
            else => std.debug.warn("EVAL\t{}\n", .{node.id}),

            .GroupedExpression => if (node.cast(zig_ast.Node.GroupedExpression)) |parensed|
                return resolve(ctx, parensed.expr, opts, null),

            .BuiltinCall => if (node.cast(zig_ast.Node.BuiltinCall)) |builtin_call| {
                const builtin_func_name = ctx.ast.tokenSlice(builtin_call.builtin_token);
                var handled = false;

                if (std.mem.eql(u8, builtin_func_name, "@import") and builtin_call.params.count() == 1) {
                    handled = true;
                    const my_dir_path = std.fs.path.dirname(ctx.src_file.full_path) orelse ".";
                    for (try resolve(ctx, builtin_call.params.at(0).*, .{}, null)) |import| switch (import) {
                        else => {},
                        .lit_str => |str| {
                            var import_path = str;
                            const is_std = std.mem.eql(u8, "std", str);
                            if (!std.mem.endsWith(u8, str, ".zig")) {
                                if (is_std or std.mem.eql(u8, "builtin", str))
                                    if (ctx.src_file.sess.zig_install.stdLibDirPath()) |std_lib_dir_path| {
                                        if (std.fs.path.resolve(ctx.memTempAlloc(), &[_]Str{ std_lib_dir_path, if (!is_std) "builtin.zig" else "std.zig" })) |file_abs_path|
                                            import_path = file_abs_path
                                        else |err| switch (err) {
                                            else => {},
                                            error.OutOfMemory => return error.OutOfMemory,
                                        }
                                    };
                            }
                            if (std.mem.endsWith(u8, import_path, ".zig")) {
                                if (std.fs.path.resolve(ctx.memTempAlloc(), &[_]Str{ my_dir_path, import_path })) |file_abs_path| {
                                    try ctx.src_file.sess.src_files.ensureFilesTracked(ctx.memTempArena(), &[_]SrcFiles.EnsureTracked{.{ .absolute_path = file_abs_path }});
                                    if (try ctx.extra(file_abs_path)) |sub_ctx|
                                        try ret.appendSlice(try resolve(sub_ctx, &sub_ctx.ast.root_node.base, .{}, null));
                                } else |err| switch (err) {
                                    else => {},
                                    error.OutOfMemory => return error.OutOfMemory,
                                }
                            }
                        },
                    };
                }

                if (!handled)
                    std.debug.warn("EVAL BCALL\t{}\n", .{builtin_func_name});
            },

            .SuffixOp => if (node.cast(zig_ast.Node.SuffixOp)) |suffix_op_node| switch (suffix_op_node.op) {
                else => std.debug.warn("EVAL SUFFIX-OP\t{}\n", .{suffix_op_node.op}),
                .ArrayInitializer => |*arr_init| {
                    const elems = try ctx.memTempAlloc().alloc([]const Resolved, arr_init.count());
                    var iter = arr_init.iterator(0);
                    var i: usize = 0;
                    while (iter.next()) |node_ptr_ptr| : (i += 1)
                        elems[i] = try resolve(ctx, node_ptr_ptr.*, .{}, null);

                    const bulk = try zag.mem.inOrderPermutations(Resolved, ctx.memTempAlloc(), elems);
                    i = 0;
                    while (i < bulk.len) : (i += elems.len)
                        try ret.append(.{ .lit_arr = bulk[i .. i + elems.len] });
                },
            },

            .InfixOp => if (node.cast(zig_ast.Node.InfixOp)) |infix_op_node| switch (infix_op_node.op) {
                else => std.debug.warn("EVAL: INFIX-OP\t{}\n", .{infix_op_node.op}),
                .Add => try evalInfixOp(ctx, infix_op_node, &ret, primOpAdd, comptime of(@TagType(Resolved), .{ .lit_float, .lit_int }), null),
                .AddWrap => try evalInfixOp(ctx, infix_op_node, &ret, primOpAddWrap, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .Sub => try evalInfixOp(ctx, infix_op_node, &ret, primOpSub, comptime of(@TagType(Resolved), .{ .lit_float, .lit_int }), null),
                .SubWrap => try evalInfixOp(ctx, infix_op_node, &ret, primOpSubWrap, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .Mul => try evalInfixOp(ctx, infix_op_node, &ret, primOpMul, comptime of(@TagType(Resolved), .{ .lit_float, .lit_int }), null),
                .MulWrap => try evalInfixOp(ctx, infix_op_node, &ret, primOpMulWrap, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .Div => try evalInfixOp(ctx, infix_op_node, &ret, primOpDiv, comptime of(@TagType(Resolved), .{ .lit_float, .lit_int }), null),
                .Mod => try evalInfixOp(ctx, infix_op_node, &ret, primOpMod, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .BangEqual => try evalInfixOp(ctx, infix_op_node, &ret, primOpNeq, comptime of(@TagType(Resolved), .{ .lit_int, .lit_float, .lit_bool }), .lit_bool),
                .EqualEqual => try evalInfixOp(ctx, infix_op_node, &ret, primOpEq, comptime of(@TagType(Resolved), .{ .lit_int, .lit_float, .lit_bool }), .lit_bool),
                .BitAnd => try evalInfixOp(ctx, infix_op_node, &ret, primOpBitAnd, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .BitOr => try evalInfixOp(ctx, infix_op_node, &ret, primOpBitOr, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .BitXor => try evalInfixOp(ctx, infix_op_node, &ret, primOpBitXor, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .BoolAnd => try evalInfixOp(ctx, infix_op_node, &ret, primOpBoolAnd, comptime of(@TagType(Resolved), .{.lit_bool}), .lit_bool),
                .BoolOr => try evalInfixOp(ctx, infix_op_node, &ret, primOpBoolOr, comptime of(@TagType(Resolved), .{.lit_bool}), .lit_bool),
                .BitShiftLeft => try evalInfixOp(ctx, infix_op_node, &ret, primOpBitShiftLeft, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .BitShiftRight => try evalInfixOp(ctx, infix_op_node, &ret, primOpBitShiftRight, comptime of(@TagType(Resolved), .{.lit_int}), null),
                .GreaterOrEqual => try evalInfixOp(ctx, infix_op_node, &ret, primOpGeq, comptime of(@TagType(Resolved), .{ .lit_int, .lit_float }), .lit_bool),
                .LessOrEqual => try evalInfixOp(ctx, infix_op_node, &ret, primOpLeq, comptime of(@TagType(Resolved), .{ .lit_int, .lit_float }), .lit_bool),
                .GreaterThan => try evalInfixOp(ctx, infix_op_node, &ret, primOpGt, comptime of(@TagType(Resolved), .{ .lit_int, .lit_float }), .lit_bool),
                .LessThan => try evalInfixOp(ctx, infix_op_node, &ret, primOpLt, comptime of(@TagType(Resolved), .{ .lit_int, .lit_float }), .lit_bool),
                .Period => {
                    const foo1 = 10 != 1;
                    const foo2 = true or (foo != foo);
                    var foo4 = foo2;
                    const foo3 = true and false;
                    // const all_lhs = try resolve(ctx, infix_op_node.lhs, .{}, null);
                    // const all_rhs = try resolve(ctx, infix_op_node.rhs, .{}, null);
                    // for (all_lhs) |lhs| for (all_rhs) |rhs| {
                    //     std.debug.warn("DOT\t{}\t{}\n", .{ std.meta.activeTag(lhs), std.meta.activeTag(rhs) });
                    // };
                },
                .ArrayCat => {
                    const all_lhs = try resolve(ctx, infix_op_node.lhs, .{}, null);
                    const all_rhs = try resolve(ctx, infix_op_node.rhs, .{}, null);
                    for (all_lhs) |lhs| for (all_rhs) |rhs| {
                        switch (lhs) {
                            else => std.debug.warn("ArrayCat lhs: {}\n", .{std.meta.activeTag(lhs)}),
                            .lit_str => |l_str| switch (rhs) {
                                else => std.debug.warn("ArrayCat rhs: {}\n", .{std.meta.activeTag(rhs)}),
                                .lit_str => |r_str| {
                                    var str = try ctx.memTempAlloc().alloc(u8, l_str.len + r_str.len);
                                    std.mem.copy(u8, str[0..l_str.len], l_str);
                                    std.mem.copy(u8, str[l_str.len..], r_str);
                                    try ret.append(.{ .lit_str = str });
                                },
                                .lit_arr => if (try rhs.arrToStr(ctx.memTempAlloc())) |r| {
                                    var str = try ctx.memTempAlloc().alloc(u8, l_str.len + r.lit_str.len);
                                    std.mem.copy(u8, str[0..l_str.len], l_str);
                                    std.mem.copy(u8, str[l_str.len..], r.lit_str);
                                    try ret.append(.{ .lit_str = str });
                                },
                            },
                            .lit_arr => |l_arr| switch (rhs) {
                                else => std.debug.warn("ArrayCat rhs: {}\n", .{std.meta.activeTag(rhs)}),
                                .lit_str => |r_str| if (try lhs.arrToStr(ctx.memTempAlloc())) |l| {
                                    var str = try ctx.memTempAlloc().alloc(u8, l.lit_str.len + r_str.len);
                                    std.mem.copy(u8, str[0..l.lit_str.len], l.lit_str);
                                    std.mem.copy(u8, str[l.lit_str.len..], r_str);
                                    try ret.append(.{ .lit_str = str });
                                },
                                .lit_arr => |r_arr| {
                                    var arr = try ctx.memTempAlloc().alloc(Resolved, l_arr.len + r_arr.len);
                                    std.mem.copy(Resolved, arr[0..l_arr.len], l_arr);
                                    std.mem.copy(Resolved, arr[l_arr.len..], r_arr);
                                    try ret.append(.{ .lit_arr = arr });
                                },
                            },
                        }
                    };
                },
            },

            .StringLiteral, .CharLiteral => {
                const maybe_str_lit = node.cast(zig_ast.Node.StringLiteral);
                const maybe_char_lit = node.cast(zig_ast.Node.CharLiteral);
                const tok = if (maybe_str_lit) |str_lit|
                    ctx.ast.tokenSlice(str_lit.token)
                else if (maybe_char_lit) |char_lit| rewrite_quotes: {
                    var copy = try std.mem.dupe(ctx.memTempAlloc(), u8, ctx.ast.tokenSlice(char_lit.token));
                    copy[0] = '"';
                    copy[copy.len - 1] = '"';
                    break :rewrite_quotes copy;
                } else
                    unreachable;
                var bad_index: usize = undefined;
                if (std.zig.parseStringLiteral(ctx.memTempAlloc(), tok, &bad_index)) |str_val|
                    try ret.append(.{ .lit_str = str_val })
                else |err|
                    try ret.append(.{
                        .err_or_warning = try std.fmt.allocPrint(ctx.
                            memTempAlloc(), "`{}` at index {}", .{ @errorName(err), bad_index }),
                    });
            },

            .BoolLiteral => if (node.cast(zig_ast.Node.BoolLiteral)) |bool_lit| {
                const tok = ctx.ast.tokenSlice(bool_lit.token);
                if (std.mem.eql(u8, "true", tok))
                    try ret.append(.{ .lit_bool = true })
                else if (std.mem.eql(u8, "false", tok))
                    try ret.append(.{ .lit_bool = false })
                else
                    try ret.append(.{
                        .err_or_warning = try std.fmt.allocPrint(ctx.
                            memTempAlloc(), "invalid `bool` literal: `{s}`", .{tok}),
                    });
            },

            .FloatLiteral => if (node.cast(zig_ast.Node.FloatLiteral)) |float_lit| {
                const tok = ctx.ast.tokenSlice(float_lit.token);
                if (std.fmt.parseFloat(f64, tok)) |float|
                    try ret.append(.{ .lit_float = float })
                else |err|
                    try ret.append(.{ .err_or_warning = @errorName(err) });
            },

            .IntegerLiteral => if (node.cast(zig_ast.Node.IntegerLiteral)) |int_lit| {
                const tok = ctx.ast.tokenSlice(int_lit.token);
                var start: usize = 0;
                var radix: u8 = 10;
                if (tok[start] == '0' and tok[start..].len > 2) switch (tok[start + 1]) {
                    else => {},
                    'x', 'X' => {
                        start += 2;
                        radix = 16;
                    },
                    'o', 'O' => {
                        start += 2;
                        radix = 8;
                    },
                    'b', 'B' => {
                        start += 2;
                        radix = 2;
                    },
                };
                if (start < tok.len)
                    if (std.fmt.parseInt(u128, tok[start..], radix)) |int|
                        try ret.append(.{ .lit_int = int })
                    else |err|
                        try ret.append(.{ .err_or_warning = @errorName(err) });
            },

            .Identifier => if (node.cast(zig_ast.Node.Identifier)) |ident| {
                const ident_name = ctx.ast.tokenSlice(ident.token);

                inline for (std.meta.fields(Resolved.TypeDesc.PrimType)) |*field, field_idx|
                    if (ret.len == 0 and std.mem.eql(u8, ident_name, field.name))
                        try ret.append(.{ .type_desc = .{ .prim = @intToEnum(Resolved.TypeDesc.PrimType, field_idx) } });
                if (ret.len == 0 and std.mem.eql(u8, ident_name, "comptime_int"))
                    try ret.append(.{ .type_desc = .{ .int = .{ .unsigned = true } } });
                if (ret.len == 0 and std.mem.eql(u8, ident_name, "comptime_float"))
                    try ret.append(.{ .type_desc = .{ .float = .{} } });
                if (ret.len == 0 and ident_name.len > 1 and
                    (ident_name[0] == 'u' or ident_name[0] == 'i' or ident_name[0] == 'f') and
                    ident_name[1] >= '0' and ident_name[1] <= '9')
                {
                    if (std.fmt.parseUnsigned(u16, ident_name[1..], 10)) |bit_width|
                        try ret.append(.{
                            .type_desc = switch (ident_name[0]) {
                                else => unreachable,
                                'i' => Resolved.TypeDesc{ .int = .{ .unsigned = false, .bit_width = bit_width } },
                                'u' => Resolved.TypeDesc{ .int = .{ .unsigned = true, .bit_width = bit_width } },
                                'f' => Resolved.TypeDesc{ .float = .{ .bit_width = bit_width } },
                            },
                        })
                    else |_| {}
                }

                if (ret.len == 0) {
                    const node_path_maybe = if (maybe_path_to_node != null) maybe_path_to_node else (try pathToNode(ctx, .{ .node = node }));
                    if (node_path_maybe) |node_path|
                        if (parentDotExpr(ctx.memTempArena(), node_path, true)) |infix_op_node|
                            if (node != nestedInfixOpLeftMostOperand(infix_op_node))
                                return resolve(ctx, &infix_op_node.base, opts, node_path_maybe);

                    if (node_path_maybe) |node_path| {
                        var i_p: usize = node_path.len - 2;
                        var usings = std.ArrayList(*zig_ast.Node.Use).init(ctx.memTempAlloc());
                        while (i_p >= 0) {
                            const this_parent_node = node_path[i_p];
                            var i_c: usize = 0;
                            while (this_parent_node.iterate(i_c)) |actual_sub_node| : (i_c += 1) {
                                var name_tok_idx: ?zig_ast.TokenIndex = null;
                                const sub_node = unParensed(actual_sub_node);
                                switch (sub_node.id) {
                                    else => {},
                                    .VarDecl => name_tok_idx = sub_node.cast(zig_ast.Node.VarDecl).?.name_token,
                                    .FnProto => name_tok_idx = sub_node.cast(zig_ast.Node.FnProto).?.name_token,
                                    .ParamDecl => name_tok_idx = sub_node.cast(zig_ast.Node.ParamDecl).?.name_token,
                                    .Block => name_tok_idx = sub_node.cast(zig_ast.Node.Block).?.label,
                                    .ErrorTag => name_tok_idx = sub_node.cast(zig_ast.Node.ErrorTag).?.name_token,
                                    .Payload => name_tok_idx = sub_node.cast(zig_ast.Node.Payload).?.error_symbol.cast(zig_ast.Node.Identifier).?.token,
                                    .PointerPayload => name_tok_idx = sub_node.cast(zig_ast.Node.PointerPayload).?.value_symbol.cast(zig_ast.Node.Identifier).?.token,
                                    .PointerIndexPayload => if (sub_node.cast(zig_ast.Node.PointerIndexPayload)) |it| {
                                        name_tok_idx = it.value_symbol.cast(zig_ast.Node.Identifier).?.token;
                                        if (it.index_symbol) |node_index_symbol| {
                                            if (name_tok_idx == null or !std.mem.eql(u8, ctx.ast.tokenSlice(name_tok_idx.?), ident_name))
                                                name_tok_idx = node_index_symbol.cast(zig_ast.Node.Identifier).?.token;
                                        }
                                    },
                                    .Use => if (sub_node.cast(zig_ast.Node.Use)) |it|
                                        try usings.append(it),
                                }
                                if (name_tok_idx) |name_index| {
                                    if (std.mem.eql(u8, ctx.ast.tokenSlice(name_index), ident_name))
                                        try ret.append(.{ .loc_ref = .{ .ctx = ctx, .node = sub_node } });
                                }
                            }
                            if (i_p == 0) break else i_p -= 1;
                        }
                        if (ret.len == 0 and usings.len != 0) {
                            var into = std.StringHashMap(std.ArrayList(zast.LocRef)).init(ctx.memTempAlloc());
                            try gatherUsingDeclsInScope(ctx, &into, usings.toSliceConst(), false, ident_name);
                            if (into.getValue(ident_name)) |loc_refs| for (loc_refs.items[0..loc_refs.len]) |loc_ref|
                                try ret.append(.{ .loc_ref = loc_ref });
                        }
                    }
                }
            },

            .VarDecl => if (node.cast(zig_ast.Node.VarDecl)) |var_decl| {
                if (var_decl.init_node) |init_node|
                    try ret.appendSlice(try resolve(ctx, init_node, opts, null));
            },

            .Root => if (node.cast(zig_ast.Node.Root)) |cont_root| {
                var iter = cont_root.decls.iterator(0);
                var decls_own = std.StringHashMap(LocRef).init(ctx.memTempAlloc());
                var decls_use = std.StringHashMap(LocRef).init(ctx.memTempAlloc());
                var usings = std.ArrayList(*zig_ast.Node.Use).init(ctx.memTempAlloc());
                while (iter.next()) |decl_node_ptr_ptr| {
                    if (decl_node_ptr_ptr.*.cast(zig_ast.Node.Use)) |using|
                        try usings.append(using)
                    else if (nameFromToken(ctx.ast, decl_node_ptr_ptr.*)) |name|
                        _ = try decls_own.put(name, .{ .node = decl_node_ptr_ptr.*, .ctx = ctx });
                }
                if (usings.len != 0) {
                    var using_decls = std.StringHashMap(std.ArrayList(zast.LocRef)).init(ctx.memTempAlloc());
                    try gatherUsingDeclsInScope(ctx, &using_decls, usings.toSliceConst(), true, null);
                    var iter_using_decls = using_decls.iterator();
                    while (iter_using_decls.next()) |name_and_loc_refs| {
                        if (!decls_use.contains(name_and_loc_refs.key) and name_and_loc_refs.value.len != 0)
                            _ = try decls_use.put(name_and_loc_refs.key, name_and_loc_refs.value.items[0]);
                    }
                }
                try ret.append(.{
                    .type_desc = .{
                        .container = .{
                            .kind = .@"struct",
                            .fields = std.StringHashMap(LocRef).init(ctx.memTempAlloc()),
                            .decls_own = decls_own,
                            .decls_use = decls_use,
                        },
                    },
                });
            },

            .ContainerDecl => if (node.cast(zig_ast.Node.ContainerDecl)) |cont_decl|
                if (std.meta.stringToEnum(Resolved.TypeDesc.ContainerKind, ctx.ast.tokenSlice(cont_decl.kind_token))) |kind_tok_str| {
                    var iter = cont_decl.fields_and_decls.iterator(0);
                    var fields = std.StringHashMap(LocRef).init(ctx.memTempAlloc());
                    var decls_own = std.StringHashMap(LocRef).init(ctx.memTempAlloc());
                    var decls_use = std.StringHashMap(LocRef).init(ctx.memTempAlloc());
                    var usings = std.ArrayList(*zig_ast.Node.Use).init(ctx.memTempAlloc());
                    while (iter.next()) |decl_node_ptr_ptr| {
                        if (decl_node_ptr_ptr.*.cast(zig_ast.Node.Use)) |using|
                            try usings.append(using)
                        else if (nameFromToken(ctx.ast, decl_node_ptr_ptr.*)) |name| {
                            if (decl_node_ptr_ptr.*.cast(zig_ast.Node.ContainerField)) |_|
                                _ = try fields.put(name, .{ .node = decl_node_ptr_ptr.*, .ctx = ctx })
                            else
                                _ = try decls_own.put(name, .{ .node = decl_node_ptr_ptr.*, .ctx = ctx });
                        }
                    }
                    if (usings.len != 0) {
                        var using_decls = std.StringHashMap(std.ArrayList(zast.LocRef)).init(ctx.memTempAlloc());
                        try gatherUsingDeclsInScope(ctx, &using_decls, usings.toSliceConst(), true, null);
                        var iter_using_decls = using_decls.iterator();
                        while (iter_using_decls.next()) |name_and_loc_refs| {
                            if (!decls_use.contains(name_and_loc_refs.key) and name_and_loc_refs.value.len != 0)
                                _ = try decls_use.put(name_and_loc_refs.key, name_and_loc_refs.value.items[0]);
                        }
                    }
                    try ret.append(.{ .type_desc = .{ .container = .{ .kind = kind_tok_str, .fields = fields, .decls_own = decls_own, .decls_use = decls_use } } });
                },
        }

        if (opts.resolve_loc_refs_to_final_values) {
            var i: usize = 0;
            while (i < ret.len) switch (ret.items[i]) {
                else => i += 1,
                .loc_ref => |*loc_ref| {
                    _ = ret.swapRemove(i);
                    try ret.appendSlice(try resolve(loc_ref.ctx, loc_ref.node, opts, null));
                },
            };
        }
        ret.shrink(ret.len);
        return ret.toSliceConst();
    }

    pub const Resolving = struct {
        resolve_loc_refs_to_final_values: bool = true,
    };

    pub const LocRef = struct {
        ctx: *SrcFileAstCtx,
        node: *zig_ast.Node,

        pub fn isPub(me: *const LocRef) bool {
            const node = unParensed(me.node);
            return switch (node.id) {
                else => false,
                .FnProto => (node.cast(zig_ast.Node.FnProto).?.visib_token != null),
                .VarDecl => (node.cast(zig_ast.Node.VarDecl).?.visib_token != null),
            };
        }
    };

    pub const Resolved = union(enum) {
        loc_ref: LocRef,
        err_or_warning: Str,
        type_desc: TypeDesc,

        // instead of lit_ prefix, another nested union(enum) would have been nicer. but zig compiler assertion-crashed all over the place with that refactoring fully in place. what a way to spend a whole evening.
        lit_arr: []const Resolved,
        lit_str: Str,
        lit_int: u128, // size could be up to 1024 to fill up the union.. but over 128, LLVM barks currently (TODO: revisit occasionally)
        lit_float: f64, // std.fmt handles no bigger ones right now
        lit_bool: bool,

        pub fn arrToStr(me: Resolved, mem: *std.mem.Allocator) !?Resolved {
            switch (me) {
                else => return null,
                .lit_str => |str| return Resolved{ .lit_str = try std.mem.dupe(mem, u8, str) }, // sad to copy but caller owns return-str-if-any
                .lit_arr => |arr| {
                    var str = try mem.alloc(u8, arr.len);
                    for (arr) |item, i|
                        switch (item) {
                            else => return null,
                            .lit_int => |int| if (int >= 0 and int <= 255) {
                                str[i] = @intCast(u8, int);
                            } else {
                                return null;
                            },
                        };
                    return Resolved{ .lit_str = str };
                },
            }
        }

        pub fn typeDescFrom(mem_temp: *std.heap.ArenaAllocator, resolved: Resolved) error{OutOfMemory}!?TypeDesc {
            return switch (resolved) {
                else => null,
                .loc_ref => unreachable,
                .type_desc => |type_desc| type_desc,
                .lit_bool => TypeDesc{ .prim = .@"bool" },
                .lit_int => |int| TypeDesc{ .int = .{ .unsigned = true } },
                .lit_float => TypeDesc{ .float = .{} },
                .lit_str => TypeDesc{
                    .wrap = .{
                        .which = .slice,
                        .@"const" = true,
                        .of = try zag.mem.enHeap(&mem_temp.allocator, TypeDesc{ .int = .{ .bit_width = 8, .unsigned = true } }),
                    },
                },
                .lit_arr => |arr| TypeDesc{
                    .wrap = .{
                        .which = .{ .arr = arr.len },
                        .@"const" = true,
                        .of = try zag.mem.enHeap(&mem_temp.allocator, ((try typeDescFrom(mem_temp, arr[0])) orelse return null)),
                    },
                },
            };
        }

        // pub const Lit = union(enum) {};

        pub const TypeDesc = union(enum) {
            prim: PrimType,
            int: struct {
                bit_width: ?u16 = null,
                unsigned: bool = true,
            },
            float: struct {
                bit_width: ?u16 = null, // technically only u7 but simplifies things without breaking anything here
            },
            wrap: struct {
                of: *TypeDesc,
                @"const": bool = false,
                which: union(enum) {
                    opt,
                    ptr,
                    arr: usize,
                    slice,
                },
            },
            container: struct {
                kind: ContainerKind,
                fields: std.StringHashMap(LocRef),
                decls_own: std.StringHashMap(LocRef),
                decls_use: std.StringHashMap(LocRef),
            },

            pub const ContainerKind = enum {
                @"enum",
                @"struct",
                @"union",
            };

            pub const PrimType = enum {
                @"bool",
                @"isize",
                @"usize",
                @"c_short",
                @"c_ushort",
                @"c_int",
                @"c_uint",
                @"c_long",
                @"c_ulong",
                @"c_longlong",
                @"c_ulonglong",
                @"c_longdouble",
                @"c_void",
                @"void",
                @"noreturn",
                @"type",
                @"anyerror",
            };
        };
    };

    fn evalInfixOp(ctx: *SrcFileAstCtx, infix_op_node: *zig_ast.Node.InfixOp, ret: *std.ArrayList(Resolved), primOpFn: var, comptime prim_op_fn_field_tags: []@TagType(Resolved), comptime prim_op_fn_ret_tag: ?@TagType(Resolved)) !void {
        const err_bad_operands: Resolved = .{ .err_or_warning = "invalid or incompatible operand types" };
        const all_lhs = try resolve(ctx, infix_op_node.lhs, .{}, null);
        const all_rhs = try resolve(ctx, infix_op_node.rhs, .{}, null);
        if (all_lhs.len == 0 or all_rhs.len == 0)
            try ret.append(err_bad_operands)
        else for (all_lhs) |lhs| for (all_rhs) |rhs| {
            if (lhs == .err_or_warning)
                try ret.append(lhs)
            else if (rhs == .err_or_warning)
                try ret.append(rhs)
            else if (std.meta.activeTag(lhs) == std.meta.activeTag(rhs)) {
                if (lhs == .type_desc) {
                    //
                } else {
                    var ok = false;
                    inline for (prim_op_fn_field_tags) |prim_op_fn_field_tag| {
                        if (!ok and std.meta.activeTag(lhs) == prim_op_fn_field_tag) {
                            ok = true;
                            try ret.append(@unionInit(Resolved, @tagName(prim_op_fn_ret_tag orelse prim_op_fn_field_tag), primOpFn(@field(lhs, @tagName(prim_op_fn_field_tag)), @field(rhs, @tagName(prim_op_fn_field_tag)))));
                        }
                    }
                    if (!ok)
                        if (try Resolved.typeDescFrom(ctx.memTempArena(), lhs)) |type_desc|
                            if (type_desc == .int or type_desc == .float)
                                try ret.append(.{ .type_desc = type_desc })
                            else
                                try ret.append(err_bad_operands);
                }
            } else
                try ret.append(err_bad_operands);
        };
    }
};

usingnamespace temp_foo_1;
const temp_foo_1 = struct {
    pub usingnamespace temp_foo_2;
};
const temp_foo_2 = temp_test;
const temp_test = struct { // TODO move back up into the zast struct
    temp_unused_field: u42,

    pub fn gatherUsingDeclsInScope(
        ctx: *SrcFileAstCtx,
        into: *std.StringHashMap(std.ArrayList(zast.LocRef)),
        usings: []const *zig_ast.Node.Use,
        only_pub: bool,
        only_name: ?Str,
    ) error{OutOfMemory}!void {
        if (only_name) |needle|
            std.debug.warn("looking for:\t{}\n", .{needle});
        for (usings) |using|
            if (!only_pub or using.visib_token != null) {
                const resolveds = try zast.resolve(ctx, using.expr, .{}, null);
                for (resolveds) |resolved| {
                    std.debug.assert(resolved == .type_desc and resolved.type_desc == .container);
                    for (&[_]*const std.StringHashMap(zast.LocRef){
                        &resolved.type_desc.container.decls_own,
                        &resolved.type_desc.container.decls_use,
                    }) |decls| {
                        var iter = decls.iterator();
                        while (iter.next()) |name_and_loc_ref| {
                            const name = name_and_loc_ref.key;
                            const loc_ref = name_and_loc_ref.value;
                            if ((only_name == null or std.mem.eql(u8, name, only_name.?)) and
                                (!only_pub or loc_ref.isPub()))
                            {
                                var locrefs = into.getValue(name) orelse std.ArrayList(zast.LocRef).init(ctx.memTempAlloc());
                                try locrefs.append(loc_ref);
                                _ = try into.put(name, locrefs);
                            }
                        }
                    }
                }
            };
    }
};

fn primOpAdd(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs + rhs;
}

fn primOpBitAnd(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs & rhs;
}

fn primOpBitOr(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs | rhs;
}

fn primOpBitShiftLeft(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs << @intCast(u7, rhs);
}

fn primOpBitShiftRight(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs >> @intCast(u7, rhs);
}

fn primOpBitXor(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs ^ rhs;
}

fn primOpAddWrap(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs +% rhs;
}

fn primOpMul(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs * rhs;
}

fn primOpMulWrap(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs *% rhs;
}

fn primOpDiv(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs / rhs;
}

fn primOpNeq(lhs: var, rhs: var) bool {
    return lhs != rhs;
}

fn primOpGeq(lhs: var, rhs: var) bool {
    return lhs >= rhs;
}

fn primOpLeq(lhs: var, rhs: var) bool {
    return lhs <= rhs;
}

fn primOpGt(lhs: var, rhs: var) bool {
    return lhs > rhs;
}

fn primOpLt(lhs: var, rhs: var) bool {
    return lhs < rhs;
}

fn primOpEq(lhs: var, rhs: var) bool {
    return lhs == rhs;
}

fn primOpBoolAnd(lhs: var, rhs: var) bool {
    return lhs and rhs;
}

fn primOpBoolOr(lhs: var, rhs: var) bool {
    return lhs or rhs;
}

fn primOpMod(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs % rhs;
}

fn primOpSub(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs - rhs;
}

fn primOpSubWrap(lhs: var, rhs: var) @TypeOf(lhs) {
    return lhs -% rhs;
}
