const std = @import("std");
usingnamespace @import("../zigsess/zigsess.zig");

test "" {
    const lsp = @import("./langserv.zig");

    _ = lsp.api_server_side;
    _ = lsp.Server.forever;
    var __ = lsp.Server{ .onOutput = onOutput };

    const start_time = std.time.milliTimestamp();
    var sess = Session{};
    try sess.init(std.heap.page_allocator, "/home/_/tmp");
    defer sess.deinit();
    try sess.worker_gather_src_files.enqueueJobs(&[_]WorkerThatGathersSrcFiles.JobEntry{
        .{ .dir_added = "/home/_/c/z" },
    });
    std.time.sleep(1 * std.time.second);
    std.debug.warn("\n\n\n{}ms\n\n\n", .{std.time.milliTimestamp() - start_time});
}

fn onOutput(_: []const u8) anyerror!void {
    return;
}
