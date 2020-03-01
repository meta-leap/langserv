usingnamespace @import("./_usingnamespace.zig");

fn srcFileSymbols(comptime T: type, mem: *std.heap.ArenaAllocator, src_file_uri: Str, force_hint: ?Str) ![]T {
    const src_file_abs_path = lspUriToFilePath(src_file_uri);
    const hierarchical = (T == DocumentSymbol);
    const locked = (try zsess.src_intel.withNamedDeclsEnsured(mem, src_file_abs_path)) orelse return &[_]T{};
    defer locked.held.release();
    const intel = &locked.item.src_file.intel.?;
    const src = locked.item.ast.source;
    const decls = try intel.named_decls.?.toOrderedList(&mem.allocator, null);
    var results = try std.ArrayList(T).initCapacity(&mem.allocator, decls.len);
    var tags = std.AutoHashMap(*SrcIntel.NamedDecl, SrcIntel.NamedDecl.Kind).init(&mem.allocator);

    { // prefilter `decls` by removing unwanted nodes so we can iterate more dumbly afterwards
        var tmp = std.ArrayList(@typeInfo(@TypeOf(decls)).Pointer.child){ .len = decls.len, .items = decls, .allocator = &mem.allocator };
        var i: usize = 0;
        while (i < tmp.len) {
            var should_remove = false;
            switch (tmp.items[i].value.kind) {
                else => {},
                .FnArg, .Block, .Payload => should_remove = true,
                .IdentConst, .IdentVar, .Init => {
                    var keep = (tmp.items[i].parent == null or
                        intel.named_decls.?.get(tmp.items[i].parent.?).isContainer() or
                        try intel.named_decls.?.haveAny(&mem.allocator, SrcIntel.NamedDecl.isContainer, tmp.items[i].node_id));
                    should_remove = !keep;
                },
                .Struct, .Union, .Enum => if (tmp.items[i].parent) |parent| {
                    should_remove = (i < (tmp.len - 1) and
                        tmp.items[i - 1].node_id == parent and 1 == intel.named_decls.?.numSubNodes(parent, 2) and
                    // tmp.items[i + 1].depth > tmp.items[i].depth and tmp.items[i + 1].parent != null and tmp.items[i + 1].parent.? == tmp.items[i].node_id and
                        tmp.items[i - 1].value.kind != .Fn and tmp.items[i - 1].value.kind != .Test);
                    if (should_remove and tmp.items[i - 1].value.kind != .Field)
                        _ = try tags.put(tmp.items[i - 1].value, tmp.items[i].value.kind);
                },
            }
            if (!should_remove)
                i += 1
            else {
                var j = i + 1;
                while (j < tmp.len) : (j += 1)
                    if (tmp.items[j].depth <= tmp.items[i].depth) break else tmp.items[j].depth -= 1;
                _ = tmp.orderedRemove(i);
            }
        }
        decls = tmp.items[0..tmp.len];
    }

    var cur_path: []usize = &[_]usize{};
    for (decls) |*list_entry, i| {
        const this_decl = list_entry.value;
        const range_full = try Range.initFromResliced(src, this_decl.pos.full.start, this_decl.pos.full.end, intel.src_is_ascii_only);

        const sym_kind = switch (tags.getValue(this_decl) orelse this_decl.kind) {
            else => unreachable,
            .Test => SymbolKind.Event,
            .Fn => |fn_info| if (fn_info.returns_type) SymbolKind.TypeParameter else SymbolKind.Function,
            .Struct => SymbolKind.Struct,
            .Union => SymbolKind.Null,
            .Enum => SymbolKind.Enum,
            .Field => |field| if (field.is_struct_field) SymbolKind.Field else SymbolKind.EnumMember,
            .IdentConst => SymbolKind.Constant,
            .IdentVar => SymbolKind.Variable,
            .Init => SymbolKind.Field,
            .Using => SymbolKind.Namespace,
        };

        var sym_name = if (this_decl.pos.name) |range_name| src[range_name.start..range_name.end] else @tagName(this_decl.kind);
        if (!hierarchical and list_entry.depth != 0)
            sym_name = try std.fmt.allocPrint(&mem.allocator, "{s}{s}", .{ try zag.mem.times(&mem.allocator, list_entry.depth, "\t"[0..]), sym_name });

        var sym_hint = force_hint orelse if (this_decl.pos.brief) |range_brief| src[range_brief.start..range_brief.end] else "";
        if (null == force_hint and sym_hint.len != 0) {
            var str = try std.mem.dupe(&mem.allocator, u8, sym_hint);
            zag.mem.replaceScalars(str, "\t\r\n", ' ');
            sym_hint = try zag.mem.replace(&mem.allocator, str, "  ", " ", .repeatedly);
        }

        var this_sym = if (!hierarchical)
            T{
                .name = sym_name,
                .kind = sym_kind,
                .containerName = sym_hint,
                .location = .{
                    .uri = src_file_uri,
                    .range = range_full,
                },
            }
        else
            T{
                .kind = sym_kind,
                .name = sym_name,
                .detail = sym_hint,
                .selectionRange = range_full,
                .range = range_full,
                .children = &[_]T{},
            };

        if (!hierarchical)
            try results.append(this_sym)
        else if (list_entry.parent) |parent_decl_ptr| {
            const depth_diff = @intCast(isize, list_entry.depth) - @intCast(isize, decls[i - 1].depth);
            var dst: *T = &results.items[cur_path[0]];
            var i_path: usize = 1;
            if (depth_diff == 0) {
                // append to last-before-last children
                // modify last path with index from above
                while (i_path < cur_path.len - 1) : (i_path += 1)
                    dst = &dst.children.?[cur_path[i_path]];
                dst.children = try zag.mem.dupeAppend(&mem.allocator, dst.children.?, this_sym);
                cur_path[cur_path.len - 1] = dst.children.?.len - 1;
            } else if (depth_diff == 1) {
                // append to last-in-path children
                // append to path a 0
                while (i_path < cur_path.len) : (i_path += 1)
                    dst = &dst.children.?[cur_path[i_path]];
                dst.children = try zag.mem.dupeAppend(&mem.allocator, dst.children.?, this_sym);
                std.debug.assert(dst.children.?.len == 1);
                cur_path = try zag.mem.dupeAppend(&mem.allocator, cur_path, 0);
            } else if (depth_diff < 0) {
                // remove n from path
                // append to children
                const until = (cur_path.len - 1) - @intCast(usize, std.math.absInt(depth_diff) catch unreachable);
                while (i_path < until) : (i_path += 1)
                    dst = &dst.children.?[cur_path[i_path]];
                dst.children = try zag.mem.dupeAppend(&mem.allocator, dst.children.?, this_sym);
                cur_path = try zag.mem.dupeAppend(&mem.allocator, cur_path[0..i_path], dst.children.?.len - 1);
            } else
                unreachable;
        } else {
            try results.append(this_sym);
            cur_path = try zag.mem.dupeAppend(&mem.allocator, ([0]usize{})[0..], results.len - 1);
        }
    }

    return results.toSlice();
}

pub fn onSymbolsForDocument(ctx: Server.Ctx(DocumentSymbolParams)) !Result(?DocumentSymbols) {
    const hierarchical = ctx.inst.initialized.?.capabilities.textDocument.?.documentSymbol.?.hierarchicalDocumentSymbolSupport orelse false;
    return Result(?DocumentSymbols){
        .ok = if (hierarchical)
            .{ .hierarchy = try srcFileSymbols(DocumentSymbol, ctx.memArena(), ctx.value.textDocument.uri, null) }
        else
            .{ .flat = try srcFileSymbols(SymbolInformation, ctx.memArena(), ctx.value.textDocument.uri, null) },
    };
}

pub fn onSymbolsForWorkspace(ctx: Server.Ctx(WorkspaceSymbolParams)) error{}!Result(?[]SymbolInformation) {
    return Result(?[]SymbolInformation){ .ok = null };
}

pub fn onSymbolHighlight(ctx: Server.Ctx(DocumentHighlightParams)) !Result(?[]DocumentHighlight) {
    const src_file_uri = ctx.value.TextDocumentPositionParams.textDocument.uri;
    var syms = try ctx.mem.alloc(DocumentHighlight, 1);
    for (syms) |_, i| {
        syms[i].kind = .Text;
        syms[i].range = .{ .start = .{ .character = 0, .line = 0 }, .end = .{ .character = 0, .line = 1 } };
    }
    return Result(?[]DocumentHighlight){ .ok = syms };
}
