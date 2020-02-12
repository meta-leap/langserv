const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
const lsp = @import("../langserv.zig");
usingnamespace @import("../../jsonic/jsonic.zig").Rpc;

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: Str) !void {
    try stdout.write(out_bytes);
}

pub fn main() !u8 {
    var server = lsp.Server{ .onOutput = stdoutWrite };
    setupServer(&server);
    try server.forever(&std.io.BufferedInStream(std.os.ReadError).
        init(&std.io.getStdIn().inStream().stream).stream);
    return 1; // lsp.Server.forever does a proper os.exit(0) when so instructed by lang-client (which conventionally also launched it)
}

fn setupServer(server: *lsp.Server) void {
    server.cfg.serverInfo.?.name = "dummylangserver";
    @import("./setup.zig").setupCapabilitiesAndHandlers(server);
}
