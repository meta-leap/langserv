usingnamespace @import("./_usingnamespace.zig");

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    try onInitRegisterFileWatcher(ctx);
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\nShutdown:\t");
    return Result(void){ .ok = {} };
}

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    defer srv.cfg.capabilities = zag.mem.fullDeepCopyTo(mem_alloc, srv.cfg.capabilities) catch
        |err| @panic(@errorName(err)); // why the above: below we pass ptrs to stack-local bytes that'd be gone after returning. dont want to clutter with dozens of std.mem.dupes esp. for arrays-in-arrays (eg. slices of strings)

    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);
    setupSrcFileAndWorkFolderRelatedCapabilitiesAndHandlers(srv);

    // FORMATTING
    srv.cfg.capabilities.documentFormattingProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_formatting, onFormat);
    srv.cfg.capabilities.documentOnTypeFormattingProvider = .{
        .firstTriggerCharacter = ";",
        .moreTriggerCharacter = &[_]Str{"}"},
    };
    srv.api.onRequest(.textDocument_onTypeFormatting, onFormatOnType);

    // HOVER TOOLTIP
    srv.cfg.capabilities.hoverProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_hover, onHover);

    // SYMBOLS
    srv.cfg.capabilities.documentSymbolProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_documentSymbol, onSymbolsForDocument);
    srv.cfg.capabilities.workspaceSymbolProvider = .{ .enabled = true };
    srv.api.onRequest(.workspace_symbol, onSymbolsForWorkspace);

    // LOCATION LOOKUPS
    srv.cfg.capabilities.definitionProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_definition, onDefs);

    // AUTO-COMPLETE
    // srv.cfg.capabilities.completionProvider = .{
    //     .triggerCharacters = &[_]Str{"~"},
    //     .allCommitCharacters = &[_]Str{"\t"},
    //     .resolveProvider = true,
    // };
    // srv.api.onRequest(.textDocument_completion, onCompletion);
    // srv.api.onRequest(.completionItem_resolve, onCompletionResolve);

    // SIGNATURE TOOLTIP
    // srv.cfg.capabilities.signatureHelpProvider = .{
    //     .triggerCharacters = &[_]Str{"("},
    //     .retriggerCharacters = &[_]Str{","},
    // };
    // srv.api.onRequest(.textDocument_signatureHelp, onSignatureHelp);

    // SYMBOL HIGHLIGHT
    // srv.cfg.capabilities.documentHighlightProvider = .{ .enabled = true };
    // srv.api.onRequest(.textDocument_documentHighlight, onSymbolHighlight);
}
