const std = @import("std");
const lsp = @import("lsp");

const stdout = std.io.getStdOut();

fn stdoutWriteOrCrash(out_bytes: []const u8) !void {
    try stdout.write(out_bytes);
}

pub fn main() !u8 {
    try serveForever();

    return 1; // lsp.serveForver does a proper os.Exit(0) when so instructed by lang-client (which conventionally also launched it)
}

fn serveForever() !void {
    lsp.onOutput = stdoutWriteOrCrash;
    return lsp.serveForever(
        &std.io.getStdIn().inStream().stream,
    );
}
