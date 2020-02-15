usingnamespace @import("./_usingnamespace.zig");

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: Str) !void {
    try stdout.write(out_bytes);
}

pub fn main() !u8 {
    try zsess.initAndStart(mem_alloc, "/home/_/tmp");
    defer zsess.stopAndDeinit();

    var server = Server{ .onOutput = stdoutWrite };
    setupServer(&server);
    try server.forever(&std.io.BufferedInStream(std.os.ReadError).
        init(&std.io.getStdIn().inStream().stream).stream);
    return 1; // lsp.Server.forever does a proper os.exit(0) when so instructed by lang-client (which conventionally also launched it)
}

fn setupServer(server: *Server) void {
    server.cfg.serverInfo.?.name = "wiplangserver";
    @import("./setup.zig").setupCapabilitiesAndHandlers(server);
}
