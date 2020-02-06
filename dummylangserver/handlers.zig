const std = @import("std");

usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").JsonRpc;

pub fn setup() void {
    Server.jsonrpc.onNotify(.initialized, onInitialized);
    Server.jsonrpc.onRequest(.shutdown, onShutdown);
}

fn onInitialized(in: Arg(InitializedParams)) !void {
    try Server.jsonrpc.notify(.window_showMessage, ShowMessageParams{
        .type__ = .Warning,
        .message = "Hola Welt!",
    });
}

fn onShutdown(in: Arg(void)) Ret(void) {
    return .{ .ok = {} };
}
