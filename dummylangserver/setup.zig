const std = @import("std");

usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").Rpc;

pub fn setupCapabilitiesAndHandlers(server: *Server) void {
    server.api.onNotify(.initialized, onInitialized);
    server.api.onRequest(.shutdown, onShutdown);
}

fn onInitialized(in: Server.In(InitializedParams)) !void {
    std.debug.warn("\nINIT\t{}\n", .{in.it});
    try in.ctx.api.notify(.window_showMessage, ShowMessageParams{
        .type__ = .Warning,
        .message = try std.fmt.allocPrint(in.mem, "So it's you.. {} {}.", .{
            in.ctx.initialized.?.clientInfo.?.name,
            in.ctx.initialized.?.clientInfo.?.version,
        }),
    });
}

fn onShutdown(in: Server.In(void)) error{}!Result(void) {
    return Result(void){ .ok = {} };
}
