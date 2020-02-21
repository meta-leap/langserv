usingnamespace @import("./_usingnamespace.zig");

fn srcFileSymbols(comptime T: type, mem: *std.heap.ArenaAllocator, src_file_abs_path: Str, force_hint: ?Str) ![]T {
    const hierarchical = (T == DocumentSymbol);
    const intel = (try zsess.src_intel.fileSpecificIntelCopy(src_file_abs_path, mem)) orelse
        return &[_]T{};
    const decls = try intel.decls.toOrderedList();
    var results = try std.ArrayList(T).initCapacity(&mem.allocator, decls.len);

    for (decls) |*list_entry, i| {
        const this_decl = list_entry.item;
        const ranges = (try rangesFor(this_decl, intel.src)) orelse
            return &[_]T{};

        const sym_kind = switch (this_decl.kind) {
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
        var sym_name = if (ranges.name) |range_name|
            (try range_name.constStr(intel.src)) orelse @tagName(this_decl.kind)
        else
            @tagName(this_decl.kind);
        if (!hierarchical and list_entry.depth != 0)
            sym_name = try std.fmt.allocPrint(&mem.allocator, "{s}{s}", .{ try zag.mem.times(&mem.allocator, list_entry.depth, "\t"[0..]), sym_name });
        var sym_hint = force_hint orelse
            ((ranges.strFromAnyOf(&[_]Str{ "brief_suff", "brief" }, intel.src)) orelse @tagName(this_decl.kind));
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
        try results.append(this_sym);
    }

    return results.toSlice();
}

pub fn onSymbolsForDocument(ctx: Server.Ctx(DocumentSymbolParams)) !Result(?DocumentSymbols) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    const hierarchical = false; // ctx.inst.initialized.?.capabilities.textDocument.?.documentSymbol.?.hierarchicalDocumentSymbolSupport orelse false;
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
    var ret = TRet{
        .full = (try Range.initFromResliced(in_src, decl.
            pos.full.start, decl.pos.full.end)) orelse return null,
    };
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
