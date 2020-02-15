usingnamespace @import("./_usingnamespace.zig");

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);
    setupWorkspaceFolderAndFileRelatedCapabilitiesAndHandlers(srv);
}

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    try onInitRegisterFileWatcherAndProcessWorkspaceFolders(ctx);
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\nShutdown:\t");
    return Result(void){ .ok = {} };
}
