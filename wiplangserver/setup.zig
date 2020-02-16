usingnamespace @import("./_usingnamespace.zig");

pub fn setupCapabilitiesAndHandlers(srv: *Server) !void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);
    setupWorkspaceFolderAndFileRelatedCapabilitiesAndHandlers(srv);

    // FORMATTING
    srv.cfg.capabilities.documentFormattingProvider = .{ .enabled = true };
    srv.cfg.capabilities.documentOnTypeFormattingProvider = .{
        .firstTriggerCharacter = ";",
        .moreTriggerCharacter = try zag.mem.fullDeepCopyTo(mem_alloc, &[_]Str{ "{", "}", ")", "(", "[", "]" }),
    };
    srv.api.onRequest(.textDocument_formatting, onFormat);
    srv.api.onRequest(.textDocument_onTypeFormatting, onFormatOnType);

    // SYMBOLS
    srv.cfg.capabilities.documentSymbolProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_documentSymbol, onSymbols);
}

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    try onInitRegisterFileWatcherAndProcessWorkspaceFolders(ctx);
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\nShutdown:\t");
    return Result(void){ .ok = {} };
}
