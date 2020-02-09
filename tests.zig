const std = @import("std");

test "" {
    const lsp = @import("./langserv.zig");

    _ = lsp.api_server_side;
    _ = lsp.Server.forever;
    var src: lsp.Server = lsp.Server{ .onOutput = onOutput };
}

fn onOutput(_: []const u8) anyerror!void {
    return;
}
