const std = @import("std");
const lsp = @import("../api.zig");

usingnamespace @import("../../jsonic/api.zig").JsonRpc;

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: []const u8) !void {
    try stdout.write(out_bytes);
}

pub fn main() !u8 {
    setupServer();
    try lsp.Server.forever(
        &std.io.getStdIn().inStream().stream,
    );
    return 1; // lsp.Server.forever does a proper os.Exit(0) when so instructed by lang-client (which conventionally also launched it)
}

fn setupServer() void {
    lsp.Server.onOutput = stdoutWrite;
    lsp.Server.setup.serverInfo.?.name = "dummylangserver";
    @import("./handlers.zig").setup();
}
