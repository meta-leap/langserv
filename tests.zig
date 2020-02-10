const std = @import("std");

test "" {
    const lsp = @import("./langserv.zig");

    _ = lsp.api_server_side;
    _ = lsp.Server.forever;
    var __ = lsp.Server{ .onOutput = onOutput };

    var sess = @import("./ziglangserver/session/session.zig").Session{
        //
    };
    try sess.init(std.heap.page_allocator, "/home/_/tmp");

    sess.deinit();
}

fn onOutput(_: []const u8) anyerror!void {
    return;
}
