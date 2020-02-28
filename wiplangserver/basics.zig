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

pub fn convertPosInfoToLspRange(mem_temp: *std.heap.ArenaAllocator, src: Str, tok_pos: [2]usize, from_kind: SrcIntel.Location.PosInfoKind) ![]usize {
    const range = switch (from_kind) {
        .byte_offsets_0_based_range => try Range.initFromResliced(src, tok_pos[0], tok_pos[1]),
        .line_and_col_1_based_pos => pos2range: {
            const pos = Position{ .line = tok_pos[0] - 1, .character = tok_pos[1] - 1 };
            break :pos2range Range{ .start = pos, .end = pos };
        },
    };
    return make(&mem_temp.allocator, usize, .{ range.start.line, range.start.character, range.end.line, range.end.character });
}

pub fn convertPosInfoFromLspPos(mem_temp: *std.heap.ArenaAllocator, src: Str, pos_info: []usize, into_kind: SrcIntel.Location.PosInfoKind) !?usize {
    switch (into_kind) {
        else => return error.ToDo,
        .byte_offsets_0_based_range => {
            return (Position{ .line = pos_info[0], .character = pos_info[1] }).toByteIndexIn(src);
        },
    }
}
