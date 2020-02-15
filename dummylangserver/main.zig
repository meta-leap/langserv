const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
const lsp = @import("../langserv.zig");
usingnamespace @import("../../jsonic/jsonic.zig").Rpc;

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: Str) !void {
    try stdout.write(out_bytes);
}

pub fn main() !void {
    var server = lsp.Server{ .onOutput = stdoutWrite };
    setupServer(&server);
    try server.forever(&std.io.BufferedInStream(std.os.ReadError).
        init(&std.io.getStdIn().inStream().stream).stream);
}

fn setupServer(server: *lsp.Server) void {
    server.cfg.serverInfo.?.name = "dummylangserver";
    @import("./setup.zig").setupCapabilitiesAndHandlers(server);
}
