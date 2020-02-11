const std = @import("std");
usingnamespace @import("./ziglangserver/session/session.zig");
usingnamespace @import("./ziglangserver/session/worker_gather_src_files.zig");

test "" {
    const lsp = @import("./langserv.zig");

    _ = lsp.api_server_side;
    _ = lsp.Server.forever;
    var __ = lsp.Server{ .onOutput = onOutput };

    const start_time = std.time.milliTimestamp();
    var sess = Session{};
    try sess.init(std.heap.page_allocator, "/home/_/tmp");
    defer sess.deinit();
    try sess.worker_gather_src_files.appendJobs(&[_]WorkerThatGathersSrcFiles.JobEntry{
        .{ .dir_added = "/home/_/c/z" },
    });
    std.time.sleep(5 * std.time.second);
    std.debug.warn("\n\n\n{}\n\n\n", .{std.time.milliTimestamp() - start_time});
}

fn onOutput(_: []const u8) anyerror!void {
    return;
}
