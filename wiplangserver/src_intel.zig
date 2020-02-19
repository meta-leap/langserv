usingnamespace @import("./_usingnamespace.zig");

pub fn onHover(ctx: Server.Ctx(HoverParams)) !Result(?Hover) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.TextDocumentPositionParams.textDocument.uri);
    const markdown = try std.fmt.allocPrint(ctx.mem, "Mock hover for:\n\n```zig\n{}\n```\n\n", .{ctx.
        value.TextDocumentPositionParams.position});
    return Result(?Hover){ .ok = Hover{ .contents = MarkupContent{ .value = markdown } } };
}

fn srcFileSymbols(comptime T: type, mem: *std.heap.ArenaAllocator, src_file_abs_path: Str, force_sym_hint: ?Str) ![]T {
    const hierarchical = (T == DocumentSymbol);
    const intel = (try zsess.src_intel.fileSpecific(src_file_abs_path, mem)) orelse
        return &[_]T{};
    var results = try std.ArrayList(T).initCapacity(&mem.allocator, intel.named_decls.len);
    for (intel.named_decls) |*named_decl| {
        const ranges = (try rangesFor(named_decl, intel.src)) orelse continue;

        const sym_kind = SymbolKind.Class;
        const sym_name = if (ranges.name) |range_name|
            (try range_name.constStr(intel.src)) orelse @tagName(named_decl.info)
        else
            @tagName(named_decl.info);
        var sym_hint = force_sym_hint orelse
            ((ranges.strFromAnyOf(&[_]Str{ "brief_suff", "brief" }, intel.src)) orelse @tagName(named_decl.info));
        if (force_sym_hint == null) {
            var str = try std.mem.dupe(&mem.allocator, u8, sym_hint);
            zag.mem.replaceScalars(str, "\t\r\n", ' ');
            sym_hint = try zag.mem.replace(&mem.allocator, str, "  ", " ", .repeatedly);
        }

        var sym = if (hierarchical)
            T{
                .kind = sym_kind,
                .name = sym_name,
                .detail = sym_hint,
                .selectionRange = ranges.brief orelse ranges.name orelse ranges.full,
                .range = ranges.full,
                .children = &[_]T{},
            }
        else
            T{
                .name = sym_name,
                .kind = sym_kind,
                .containerName = sym_hint,
                .location = .{
                    .uri = try std.fmt.allocPrint(&mem.allocator, "file://{}", .{src_file_abs_path}),
                    .range = ranges.full,
                },
            };
        try results.append(sym);
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
    var symbols = try std.ArrayList(SymbolInformation).initCapacity(ctx.mem, 16 * 1024);
    var src_file_abs_paths = try zsess.src_files.allCurrentlyTrackedSrcFileAbsPaths(ctx.mem);
    for (src_file_abs_paths) |src_file_abs_path| {
        var syms = try srcFileSymbols(SymbolInformation, ctx.memArena(), src_file_abs_path, std.fs.path.dirname(src_file_abs_path) orelse ".");
        try symbols.appendSlice(syms);
    }
    logToStderr("WSSYMS {}", .{symbols.len});
    return Result(?[]SymbolInformation){ .ok = symbols.toSlice() };
}

pub fn onCompletion(ctx: Server.Ctx(CompletionParams)) !Result(?CompletionList) {
    var cmpls = try std.ArrayList(CompletionItem).initCapacity(ctx.mem, 128);
    try cmpls.append(CompletionItem{ .label = @typeName(CompletionItemKind) ++ " members:", .sortText = "000" });
    inline for (@typeInfo(CompletionItemKind).Enum.fields) |*enum_field| {
        var item = CompletionItem{
            .label = try std.fmt.allocPrint(ctx.mem, "\t.{s} =\t{d}", .{ enum_field.name, enum_field.value }),
            .kind = @intToEnum(CompletionItemKind, enum_field.value),
            .sortText = try std.fmt.allocPrint(ctx.mem, "{:0>3}", .{enum_field.value}),
            .insertText = enum_field.name,
        };
        try cmpls.append(item);
    }
    return Result(?CompletionList){ .ok = .{ .items = cmpls.items[0..cmpls.len] } };
}

pub fn onCompletionResolve(ctx: Server.Ctx(CompletionItem)) !Result(CompletionItem) {
    var item = ctx.value;
    item.detail = item.sortText;
    if (item.insertText) |insert_text|
        item.documentation = .{ .value = try std.fmt.allocPrint(ctx.mem, "Above is current `" ++ @typeName(CompletionItemKind) ++ ".sortText`, and its `.insertText` is: `\"{s}\"`.", .{insert_text}) };
    return Result(CompletionItem){ .ok = item };
}

pub fn onSignatureHelp(ctx: Server.Ctx(SignatureHelpParams)) !Result(?SignatureHelp) {
    var sigs = try ctx.mem.alloc(SignatureInformation, 3);
    for (sigs) |_, i| {
        sigs[i].label = try std.fmt.allocPrint(ctx.mem, "Signature {} label", .{i});
        sigs[i].documentation = MarkupContent{ .value = try std.fmt.allocPrint(ctx.mem, "Signature **{}** markdown with `bells` & *whistles*..", .{i}) };
        sigs[i].parameters = try ctx.mem.alloc(ParameterInformation, 2);
        sigs[i].parameters.?[0].label = try std.fmt.allocPrint(ctx.mem, "Signature {}, param 0 label", .{i});
        sigs[i].parameters.?[0].documentation = MarkupContent{ .value = try std.fmt.allocPrint(ctx.mem, "Signature **{}**, param 0 markdown with `bells` & *whistles*..", .{i}) };
        sigs[i].parameters.?[1].label = try std.fmt.allocPrint(ctx.mem, "Signature {}, param 1 label", .{i});
        sigs[i].parameters.?[1].documentation = MarkupContent{ .value = try std.fmt.allocPrint(ctx.mem, "Signature **{}**, param 1 markdown with `bells` & *whistles*..", .{i}) };
    }
    return Result(?SignatureHelp){ .ok = .{ .signatures = sigs } };
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
