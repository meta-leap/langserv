usingnamespace @import("./_usingnamespace.zig");

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);
    setupWorkspaceFolderAndFileRelatedCapabilitiesAndHandlers(srv);

    srv.cfg.capabilities.documentFormattingProvider = .{ .enabled = true };
    srv.cfg.capabilities.documentOnTypeFormattingProvider = .{ .firstTriggerCharacter = ";", .moreTriggerCharacter = &[2]Str{ "}", ";" } };
    srv.api.onRequest(.textDocument_formatting, onFormat);
    srv.api.onRequest(.textDocument_onTypeFormatting, onFormatOnType);
}

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    try onInitRegisterFileWatcherAndProcessWorkspaceFolders(ctx);
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\nShutdown:\t");
    return Result(void){ .ok = {} };
}

fn onFormat(ctx: Server.Ctx(DocumentFormattingParams)) !Result(?[]TextEdit) {
    return formatted(ctx.mem, ctx.value.textDocument.uri);
}

fn onFormatOnType(ctx: Server.Ctx(DocumentOnTypeFormattingParams)) !Result(?[]TextEdit) {
    return formatted(ctx.mem, ctx.value.TextDocumentPositionParams.textDocument.uri);
}

fn formatted(mem: *std.mem.Allocator, uri: Str) !Result(?[]TextEdit) {
    const src_file_absolute_path = lspUriToFilePath(uri);
    if (zsess.src_files.getByFullPath(src_file_absolute_path)) |src_file|
        if (try src_file.formatted(mem)) |formatted_src| {
            var edit = TextEdit{
                .newText = formatted_src,
                .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = std.math.maxInt(i32), .character = 0 } },
            };
            return Result(?[]TextEdit){ .ok = try std.mem.dupe(mem, TextEdit, &[_]TextEdit{edit}) };
        };
    return Result(?[]TextEdit){ .ok = null };
}
