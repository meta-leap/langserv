const std = @import("std");
const lsp = @import("../langserv.zig");
usingnamespace @import("../../jsonic/jsonic.zig").Rpc;

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: []const u8) !void {
    try stdout.write(out_bytes);
}

pub fn main() !u8 {
    var server = lsp.Server{ .onOutput = stdoutWrite };
    setupServer(&server);
    try server.forever(
        &std.io.getStdIn().inStream().stream,
    );
    return 1; // lsp.Server.forever does a proper os.Exit(0) when so instructed by lang-client (which conventionally also launched it)
}

fn setupServer(server: *lsp.Server) void {
    server.onOutput = stdoutWrite;
    server.cfg.serverInfo.?.name = "dummylangserver";
    @import("./setup.zig").setupCapabilitiesAndHandlers(server);
}
