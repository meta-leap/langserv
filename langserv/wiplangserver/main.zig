usingnamespace @import("./_usingnamespace.zig");

pub fn main() !u8 {
    defer if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\nExit:\t");
    std.debug.warn("Init wiplangserver...\n", .{});

    src_files_owned_by_client.init();
    defer src_files_owned_by_client.deinit();
    SrcFile.loadFromPath = loadSrcFileEitherFromFsOrFromLiveBufCache;
    SrcFiles.onIssuesRefreshed = onFreshIssuesToPublish;
    SrcFiles.onBuildRuns = onBuildRuns;
    SrcIntel.convertPosInfoToCustom = convertPosInfoToLspRange;
    SrcIntel.convertPosInfoFromCustom = convertPosInfoFromLspPos;

    try zsess.initAndStart(mem_alloc, "/tmp");
    defer zsess.stopAndDeinit();

    server.cfg.serverInfo.?.name = "wiplangserver";
    setupCapabilitiesAndHandlers(&server);
    std.debug.warn("Enter main loop...\n", .{});

    return if (server.forever(&std.io.getStdIn().inStream().stream))
        0
    else |err|
        1;
    // return if (server.forever(&std.io.BufferedInStream(std.os.ReadError).
    //     init(&std.io.getStdIn().inStream().stream).stream)) 0 else |err| 1;
}
