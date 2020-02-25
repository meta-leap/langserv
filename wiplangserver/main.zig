usingnamespace @import("./_usingnamespace.zig");

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: Str) !void {
    try stdout.write(out_bytes);
    // if (std.builtin.mode == .Debug)
    //     mem_alloc_debug.report("\n");
}

pub var server = Server{ .onOutput = stdoutWrite };

pub fn main() !u8 {
    defer if (std.builtin.mode == .Debug)
        mem_alloc_debug.report("\nExit:\t");

    src_files_owned_by_client.init();
    defer src_files_owned_by_client.deinit();
    SrcFile.loadFromPath = loadSrcFileEitherFromFsOrFromLiveBufCache;
    SrcFiles.onIssuesRefreshed = onFreshIssuesToPublish;
    SrcFiles.onIssuePosCalc = onIssuePosCalc;

    try zsess.initAndStart(mem_alloc, "/home/_/tmp");
    defer zsess.stopAndDeinit();

    server.cfg.serverInfo.?.name = "wiplangserver";
    setupCapabilitiesAndHandlers(&server);
    return if (server.forever(&std.io.BufferedInStream(std.os.ReadError).
        init(&std.io.getStdIn().inStream().stream).stream)) 0 else |err| 1;
}
