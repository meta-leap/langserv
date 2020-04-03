const std = @import("std");
usingnamespace @import("../zag/zag.zig");
usingnamespace @import("./zigsess.zig");

test "" {
    var mem_alloc = zag.debug.Allocator.init(std.heap.page_allocator);
    defer mem_alloc.report("\n\n");

    var sess = Session{};
    try sess.initAndStart(&mem_alloc.allocator, "/tmp");
    defer sess.stopAndDeinit();

    _ = ZigAst;
    _ = ZigAst.resolve;
    _ = ZigAst.Resolved.arrToStr;
    _ = ZigAst.Resolving;
    _ = ZigAst.pathToNode;
    _ = ZigAst.nodeDocComments;
    _ = ZigAst.nodeFirstSubNode;
    _ = ZigAst.nodeEncloses;
    _ = ZigAst.nestedInfixOpLeftMostOperand;
    _ = ZigAst.parentDotExpr;
    _ = SrcIntel.pathToNode;
    _ = SrcIntel.pathToNode;
    _ = SrcIntel.pathToNode;
    _ = SrcIntel.pathToNode;

    // try sess.workers.src_files_gatherer.base.appendJobs(&[_]SrcFiles.EnsureTracked{
    //     .{ .absolute_path = "/home/_/c/z", .is_dir = true },
    // });

    // std.time.sleep(8 * std.time.second);
}
