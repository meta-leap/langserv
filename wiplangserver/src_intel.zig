usingnamespace @import("./_usingnamespace.zig");

pub fn onHover(ctx: Server.Ctx(HoverParams)) !Result(?Hover) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.TextDocumentPositionParams.textDocument.uri);

    const markdown = try std.fmt.allocPrint(ctx.mem, "Mock hover for:\n\n```zig\n{}\n```\n\n", .{ctx.
        value.TextDocumentPositionParams.position});

    return Result(?Hover){ .ok = Hover{ .contents = MarkupContent{ .value = markdown } } };
}

pub fn onSymbolsForDocument(ctx: Server.Ctx(DocumentSymbolParams)) !Result(?DocumentSymbols) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    var symbols = try std.ArrayList(DocumentSymbol).initCapacity(ctx.mem, 512);

    comptime var i: usize = 0;
    inline for (@typeInfo(SymbolKind).Enum.fields) |*enum_field| {
        try symbols.append(DocumentSymbol{
            .name = enum_field.name,
            .detail = try std.fmt.allocPrint(ctx.mem, "{s}.{s} = {d}", .{ @typeName(SymbolKind), enum_field.name, enum_field.value }),
            .kind = @intToEnum(SymbolKind, enum_field.value),
            .range = Range{ .start = .{ .character = 0, .line = i }, .end = .{ .character = 22, .line = i } },
            .selectionRange = Range{ .start = .{ .character = 0, .line = i }, .end = .{ .character = 22, .line = i } },
        });
        i += 1;
    }

    return Result(?DocumentSymbols){ .ok = .{ .hierarchy = symbols.toSlice() } };
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