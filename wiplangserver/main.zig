usingnamespace @import("./_usingnamespace.zig");

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: Str) !void {
    try stdout.write(out_bytes);
    if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\n");
}

pub fn main() !u8 {
    defer if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\nExit:\t");

    try zsess.initAndStart(mem_alloc, "/home/_/tmp");
    defer zsess.stopAndDeinit();

    var server = Server{ .onOutput = stdoutWrite };
    setupServer(&server);

    return if (server.forever(&std.io.BufferedInStream(std.os.ReadError).
        init(&std.io.getStdIn().inStream().stream).stream)) 0 else |err| 1;
}

fn setupServer(server: *Server) void {
    server.cfg.serverInfo.?.name = "wiplangserver";
    @import("./setup.zig").setupCapabilitiesAndHandlers(server);
}
