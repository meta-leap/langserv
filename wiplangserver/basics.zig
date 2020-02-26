usingnamespace @import("./_usingnamespace.zig");

pub var zsess = Session{};
pub var mem_alloc = if (std.builtin.mode == .Debug) &mem_alloc_debug.allocator else std.heap.allocator;
pub var mem_alloc_debug = zag.debug.Allocator.init(std.heap.page_allocator);

const stdout = std.io.getStdOut();

fn stdoutWrite(out_bytes: Str) !void {
    try stdout.write(out_bytes);
    // if (std.builtin.mode == .Debug)
    //     mem_alloc_debug.report("\n");
}

pub var server = Server{ .onOutput = stdoutWrite };

pub inline fn lspUriToFilePath(uri: Str) Str {
    return zag.mem.trimPrefix(u8, uri, "file://");
}

// could later prepend timestamps, or turn conditional on std.built.mode, etc.
pub inline fn logToStderr(comptime fmt: Str, args: var) void {
    std.debug.warn(fmt, args);
}
