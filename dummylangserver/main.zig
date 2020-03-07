const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
const lsp = @import("../langserv.zig");
usingnamespace @import("../../jsonic/jsonic.zig").Rpc;

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: Str) !void {
    _ = try stdout.write(out_bytes);
}

pub fn main() !void {
    std.debug.warn("Init dummylangserver...\n", .{});
    var server = lsp.Server{ .onOutput = stdoutWrite };
    setupServer(&server);
    std.debug.warn("Enter main loop...\n", .{});
    try server.forever(&std.io.getStdIn().inStream().stream);
    // try server.forever(&std.io.BufferedInStream(std.os.ReadError).
    //     init(&std.io.getStdIn().inStream().stream).stream);
}

fn setupServer(server: *lsp.Server) void {
    server.cfg.serverInfo.?.name = "dummylangserver";
    @import("./setup.zig").setupCapabilitiesAndHandlers(server);
}
