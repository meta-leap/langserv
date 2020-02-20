usingnamespace @import("./_usingnamespace.zig");

fn srcFileSymbols(comptime T: type, mem: *std.heap.ArenaAllocator, src_file_abs_path: Str, force_hint: ?Str) ![]T {
    const hierarchical = (T == DocumentSymbol);
    const intel = (try zsess.src_intel.fileSpecific(src_file_abs_path, mem)) orelse
        return &[_]T{};
    var results = try mem.allocator.alloc(T, intel.named_decls.len);

    for (intel.named_decls) |*this_decl, i| {
        const ranges = (try rangesFor(this_decl, intel.src)) orelse {
            results[i].name = ""; // mark for later removal, at first need to keep indices consistent
            continue;
        };

        const sym_kind = switch (this_decl.info) {
            else => SymbolKind.File,
            .Test => SymbolKind.Event,
            .Fn => SymbolKind.Function,
            .FnArg => SymbolKind.Variable,
            .Struct => SymbolKind.Class,
            .Union => SymbolKind.Interface,
            .Enum => SymbolKind.Enum,
            .Field => |field| if (field.of_struct) SymbolKind.Field else SymbolKind.EnumMember,
            .IdentConst => SymbolKind.Constant,
            .IdentVar => SymbolKind.Variable,
        };
        const sym_name = if (ranges.name) |range_name|
            (try range_name.constStr(intel.src)) orelse @tagName(this_decl.info)
        else
            @tagName(this_decl.info);
        var sym_hint = force_hint orelse
            ((ranges.strFromAnyOf(&[_]Str{ "brief_suff", "brief" }, intel.src)) orelse @tagName(this_decl.info));
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
                .selectionRange = ranges.brief orelse ranges.name orelse ranges.full,
                .range = ranges.full,
                .children = null, // try mem.allocator.alloc(T, this_decl.sub_decls.len),
            };
        results[i] = this_sym;
    }

    var i: usize = results.len;
    while (i > 0) {
        i -= 1;
        if (intel.named_decls[i].parent_decl) |parent_decl| {
            if (!hierarchical)
                results[i].name = try std.fmt.allocPrint(&mem.allocator, "{s}{s}", .{ try zag.mem.times(&mem.allocator, intel.namedDeclDepth(i), "\t"[0..]), results[i].name })
            else {
                for (intel.named_decls[i].hierarchy_path) |pidx_and_sidx, pi| {
                    if (results[pidx_and_sidx[0]].children == null)
                        results[pidx_and_sidx[0]].children = try mem.allocator.alloc(T, intel.
                            named_decls[pidx_and_sidx[0]].sub_decls.len);
                }
                results[intel.named_decls[i].hierarchy_path[intel.named_decls[i].hierarchy_path.len - 1][0]].
                    children.?[intel.named_decls[i].hierarchy_path[intel.named_decls[i].hierarchy_path.len - 1][1]] = results[i];
                results[i].name = "";
            }
        }
    }
    var results_list = std.ArrayList(T){ .len = results.len, .items = results, .allocator = &mem.allocator };
    i = results_list.len;
    while (i > 0) {
        i -= 1;
        if (results_list.items[i].name.len == 0)
            _ = results_list.orderedRemove(i);
    }
    results = results_list.toOwnedSlice();
    return results;
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
    var symbols = try std.ArrayList(SymbolInformation).initCapacity(ctx.mem, 16 * 1024);
    var src_file_abs_paths = try zsess.src_files.allCurrentlyTrackedSrcFileAbsPaths(ctx.mem);
    for (src_file_abs_paths) |src_file_abs_path| {
        var syms = try srcFileSymbols(SymbolInformation, ctx.memArena(), src_file_abs_path, std.fs.path.dirname(src_file_abs_path) orelse ".");
        try symbols.appendSlice(syms);
    }
    logToStderr("WSSYMS {}", .{symbols.len});
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

inline fn rangesFor(named_decl: *SrcFile.Intel.NamedDecl, in_src: Str) !?struct {
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
    var ret = TRet{
        .full = (try Range.initFromResliced(in_src, named_decl.
            pos.full.start, named_decl.pos.full.end)) orelse return null,
    };
    if (named_decl.pos.name) |pos_name|
        ret.name = try Range.initFromResliced(in_src, pos_name.start, pos_name.end);
    if (named_decl.pos.brief) |pos_brief|
        ret.brief = try Range.initFromResliced(in_src, pos_brief.start, pos_brief.end);
    if (named_decl.pos.brief_pref) |pos_brief_pref|
        ret.brief_pref = try Range.initFromResliced(in_src, pos_brief_pref.start, pos_brief_pref.end);
    if (named_decl.pos.brief_suff) |pos_brief_suff|
        ret.brief_suff = try Range.initFromResliced(in_src, pos_brief_suff.start, pos_brief_suff.end);
    return ret;
}
