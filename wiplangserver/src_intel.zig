usingnamespace @import("./_usingnamespace.zig");

pub fn onHover(ctx: Server.Ctx(HoverParams)) !Result(?Hover) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.TextDocumentPositionParams.textDocument.uri);

    const markdown = try std.fmt.allocPrint(ctx.mem, "Mock hover for:\n\n```zig\n{}\n```\n\n", .{ctx.
        value.TextDocumentPositionParams.position});

    return Result(?Hover){ .ok = Hover{ .contents = MarkupContent{ .value = markdown } } };
}

pub fn onSymbolsForDocument(ctx: Server.Ctx(DocumentSymbolParams)) !Result(?DocumentSymbols) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    var result = std.ArrayList(DocumentSymbol).init(ctx.mem);

    if (zsess.src_intel.fileSpecificIntel(src_file_abs_path)) |intel| {
        logToStderr("YAY\t{}\n", .{intel.named_decls.len});
        result = try std.ArrayList(DocumentSymbol).initCapacity(ctx.mem, intel.named_decls.len);
        for (intel.named_decls) |*named_decl|
            if (try Range.initFromSlice(intel.src, named_decl.pos.full_decl.start, named_decl.pos.full_decl.end)) |range_full| {
                logToStderr("RAY 1\t{}\n", .{range_full});
                var range_brief_maybe: ?Range = null;
                var range_name_maybe: ?Range = null;
                if (named_decl.pos.name) |pos_name| {
                    range_name_maybe = try Range.initFromSlice(intel.src, pos_name.start, pos_name.end);
                }
                if (named_decl.pos.brief) |pos_brief| {
                    range_brief_maybe = try Range.initFromSlice(intel.src, pos_brief.start, pos_brief.end);
                }
                logToStderr("RAY 2\t{}\n", .{named_decl.pos});
                var sym = DocumentSymbol{
                    .kind = .Class,
                    .name = if (range_name_maybe) |range_name|
                        (try range_name.sliceConst(intel.src)) orelse @tagName(named_decl.info)
                    else
                        @tagName(named_decl.info),
                    .detail = if (range_brief_maybe) |range_brief|
                        (try range_brief.sliceConst(intel.src)) orelse @tagName(named_decl.info)
                    else
                        @tagName(named_decl.info),
                    .selectionRange = range_brief_maybe orelse range_full,
                    .range = range_full,
                    .children = &[_]DocumentSymbol{},
                };
                logToStderr("RAY 3\t{}\n", .{sym});
                try result.append(sym);
                logToStderr("RAY 4\t{}\n", .{result.len});
            };
    }

    return Result(?DocumentSymbols){ .ok = .{ .hierarchy = result.toSlice() } };
}

pub fn onSymbolsForWorkspace(ctx: Server.Ctx(WorkspaceSymbolParams)) !Result(?[]SymbolInformation) {
    var symbols = try std.ArrayList(SymbolInformation).initCapacity(ctx.mem, 2048);

    comptime var i: usize = 0;
    inline for (@typeInfo(SymbolKind).Enum.fields) |*enum_field| {
        try symbols.append(SymbolInformation{
            .name = enum_field.name,
            .containerName = @typeName(SymbolKind),
            .kind = @intToEnum(SymbolKind, enum_field.value),
            .location = .{
                .uri = "file:///home/_/c/z/langserv/src/lsp_server.zig",
                .range = Range{ .start = .{ .character = 0, .line = i }, .end = .{ .character = 22, .line = i } },
            },
        });
        i += 1;
    }

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
