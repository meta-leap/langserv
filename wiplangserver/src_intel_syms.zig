usingnamespace @import("./_usingnamespace.zig");

fn srcFileSymbols(comptime T: type, mem: *std.heap.ArenaAllocator, src_file_abs_path: Str, force_hint: ?Str) ![]T {
    const hierarchical = (T == DocumentSymbol);
    const intel_shared = (try zsess.src_intel.fileSpecificIntelLocked(mem, src_file_abs_path, true)) orelse
        return &[_]T{};
    defer intel_shared.held.release();
    const intel = intel_shared.item;
    const decls = try intel.decls.toOrderedList(&mem.allocator, null);
    var results = try std.ArrayList(T).initCapacity(&mem.allocator, decls.len);

    { // prefilter `decls` by removing unwanted nodes so we can iterate more dumbly afterwards
        var tmp = std.ArrayList(@typeInfo(@TypeOf(decls)).Pointer.child){ .len = decls.len, .items = decls, .allocator = &mem.allocator };
        var i: usize = 0;
        while (i < tmp.len) {
            var should_remove = false;
            switch (tmp.items[i].value.kind) {
                else => {},
                .FnArg => should_remove = true,
                .IdentConst, .IdentVar, .Init => {
                    var keep = (tmp.items[i].parent == null or
                        intel.decls.get(tmp.items[i].parent.?).isContainer() or
                        try intel.decls.haveAny(SrcFile.Intel.Decl.isContainer, tmp.items[i].node_id));
                    should_remove = !keep;
                },
                .Struct, .Union, .Enum => if (tmp.items[i].parent) |parent| {
                    should_remove = (i < (tmp.len - 1) and
                        tmp.items[i - 1].node_id == parent and 1 == intel.decls.numSubNodes(parent, 2) and
                    // tmp.items[i + 1].depth > tmp.items[i].depth and tmp.items[i + 1].parent != null and tmp.items[i + 1].parent.? == tmp.items[i].node_id and
                        tmp.items[i - 1].value.kind != .Fn and tmp.items[i - 1].value.kind != .Test);
                    if (should_remove and tmp.items[i - 1].value.kind != .Field)
                        tmp.items[i - 1].value.tag = tmp.items[i].value.kind;
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
        const ranges = (try rangesFor(this_decl, intel.src)) orelse
            return &[_]T{};

        const sym_kind = switch (this_decl.tag orelse this_decl.kind) {
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
        var sym_name = if (ranges.name) |range_name|
            (try range_name.constStr(intel.src)) orelse @tagName(this_decl.kind)
        else
            @tagName(this_decl.kind);
        if (!hierarchical and list_entry.depth != 0)
            sym_name = try std.fmt.allocPrint(&mem.allocator, "{s}{s}", .{ try zag.mem.times(&mem.allocator, list_entry.depth, "\t"[0..]), sym_name });
        var sym_hint = force_hint orelse
            ((ranges.strFromAnyOf(&[_]Str{ "brief_suff", "brief" }, intel.src)) orelse "");
        if (force_hint == null) {
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
                    .uri = try std.fmt.allocPrint(&mem.allocator, "file://{s}", .{src_file_abs_path}),
                    .range = ranges.full,
                },
            }
        else
            T{
                .kind = sym_kind,
                .name = sym_name,
                .detail = sym_hint,
                .selectionRange = ranges.name orelse ranges.full,
                .range = ranges.full,
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
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    const hierarchical = ctx.inst.initialized.?.capabilities.textDocument.?.documentSymbol.?.hierarchicalDocumentSymbolSupport orelse false;
    return Result(?DocumentSymbols){
        .ok = if (hierarchical)
            .{ .hierarchy = try srcFileSymbols(DocumentSymbol, ctx.memArena(), src_file_abs_path, null) }
        else
            .{ .flat = try srcFileSymbols(SymbolInformation, ctx.memArena(), src_file_abs_path, null) },
    };
}

pub fn onSymbolsForWorkspace(ctx: Server.Ctx(WorkspaceSymbolParams)) !Result(?[]SymbolInformation) {
    const start_time = std.time.milliTimestamp();
    var symbols = try std.ArrayList(SymbolInformation).initCapacity(ctx.mem, 64 * 1024);
    var src_file_abs_paths = try zsess.src_files.allCurrentlyTrackedSrcFileAbsPaths(ctx.mem);
    for (src_file_abs_paths) |src_file_abs_path| {
        const src_file_uri = try std.fmt.allocPrint(ctx.mem, "file://{s}", .{src_file_abs_path});
        const sym_cont = std.fs.path.dirname(src_file_abs_path) orelse ".";
        const intel_shared = (try zsess.src_intel.fileSpecificIntelLocked(ctx.memArena(), src_file_abs_path, false)) orelse
            continue;
        defer intel_shared.held.release();
        const intel = intel_shared.item;
        for (intel.decls.all_nodes.items[0..intel.decls.all_nodes.len]) |*node, i| {
            const this_decl = &node.payload;

            const sym_kind = switch (this_decl.tag orelse this_decl.kind) {
                else => continue,
                .Fn => |fn_info| if (fn_info.returns_type) SymbolKind.TypeParameter else SymbolKind.Function,
                .Struct => SymbolKind.Struct,
                .Union => SymbolKind.Null,
                .Enum => SymbolKind.Enum,
                .IdentConst => if (node.parent == null) SymbolKind.Constant else continue,
                .IdentVar => if (node.parent == null) SymbolKind.Variable else continue,
            };

            if (this_decl.pos.name) |pos_name|
                try symbols.append(.{
                    .name = try std.mem.dupe(ctx.mem, u8, intel.src[pos_name.start..pos_name.end]),
                    .kind = sym_kind,
                    .containerName = sym_cont,
                    .location = .{
                        .uri = src_file_uri,
                        .range = try Range.initFromResliced(intel.src, pos_name.start, pos_name.end),
                    },
                });
        }
    }
    const time_taken = std.time.milliTimestamp() - start_time;
    logToStderr("WsS {}\t{}\n", .{ time_taken, symbols.len });
    return Result(?[]SymbolInformation){ .ok = symbols.toSlice() };
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

inline fn rangesFor(decl: *const SrcFile.Intel.Decl, in_src: Str) !?struct {
    full: Range = null, // TODO: Zig should compileError here! but in minimal repro it does. so leave it for now, but report before Zig 1.0.0 if it doesn't get fixed by chance in the meantime
    name: ?Range = null,
    brief: ?Range = null,
    brief_pref: ?Range = null,
    brief_suff: ?Range = null,

    pub fn strFromAnyOf(me: *const @This(), comptime field_names_to_try: []Str, in_src: Str) ?Str {
        inline for (field_names_to_try) |field_name|
            if (@field(me, field_name)) |range| {
                if (range.constStr(in_src)) |maybe_str| {
                    if (maybe_str) |str|
                        return str;
                } else |_| {}
            };
        return null;
    }
} {
    const TRet = @typeInfo(@typeInfo(@TypeOf(rangesFor).ReturnType).ErrorUnion.payload).Optional.child;
    var ret = TRet{ .full = try Range.initFromResliced(in_src, decl.pos.full.start, decl.pos.full.end) };
    if (decl.pos.name) |pos_name|
        ret.name = try Range.initFromResliced(in_src, pos_name.start, pos_name.end);
    if (decl.pos.brief) |pos_brief|
        ret.brief = try Range.initFromResliced(in_src, pos_brief.start, pos_brief.end);
    if (decl.pos.brief_pref) |pos_brief_pref|
        ret.brief_pref = try Range.initFromResliced(in_src, pos_brief_pref.start, pos_brief_pref.end);
    if (decl.pos.brief_suff) |pos_brief_suff|
        ret.brief_suff = try Range.initFromResliced(in_src, pos_brief_suff.start, pos_brief_suff.end);
    return ret;
}
