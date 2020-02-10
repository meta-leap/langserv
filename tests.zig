const std = @import("std");

test "" {
    const lsp = @import("./langserv.zig");

    _ = lsp.api_server_side;
    _ = lsp.Server.forever;
    var __ = lsp.Server{ .onOutput = onOutput };

    const start_time = std.time.milliTimestamp();
    var sess = @import("./ziglangserver/session/session.zig").Session{};
    try sess.init(std.heap.page_allocator, "/tmp");
    defer sess.deinit();
    std.debug.warn("\n\n\n{}\n\n\n", .{std.time.milliTimestamp() - start_time});
}

fn onOutput(_: []const u8) anyerror!void {
    return;
}
