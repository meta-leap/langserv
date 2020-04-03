const std = @import("std");
usingnamespace @import("../zag/zag.zig");
usingnamespace @import("../zigsess/zigsess.zig");

test "" {
    var mem_alloc = zag.debug.Allocator.init(std.heap.page_allocator);
    defer mem_alloc.report("\n\n");

    const lsp = @import("./langserv.zig");

    _ = lsp.api_server_side;
    _ = lsp.Server.forever;
    var __ = lsp.Server{ .onOutput = onOutput };
}

fn onOutput(_: []const u8) anyerror!void {
    return;
}
