usingnamespace @import("./_usingnamespace.zig");

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);
    setupWorkspaceFolderAndFileRelatedCapabilitiesAndHandlers(srv);

    srv.cfg.capabilities.documentFormattingProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_formatting, onFormat);
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
    const src_file_absolute_path = lspUriToFilePath(ctx.value.textDocument.uri);
    if (zsess.src_files.getByFullPath(src_file_absolute_path)) |src_file| {
        if (try src_file.formatted(ctx.mem)) |old_and_new| ok: {
            var edit = TextEdit{
                .newText = old_and_new[1],
                .range = (Range.initFrom(old_and_new[0]) catch break :ok) orelse break :ok,
            };
            return Result(?[]TextEdit){ .ok = try std.mem.dupe(ctx.mem, TextEdit, &[_]TextEdit{edit}) };
        }
    }
    return Result(?[]TextEdit){ .ok = null };
}
