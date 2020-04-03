const std = @import("std");
usingnamespace @import("../zag.zig");

var rnd: ?std.rand.Pcg = null;

pub fn uniqueishId(mem: *std.mem.Allocator, prefix: Str) !Str {
    if (rnd == null)
        rnd = std.rand.Pcg.init(std.time.milliTimestamp());
    return std.fmt.allocPrint(mem, "{s}_{}_{}", .{ prefix, rnd.?.next(), std.time.milliTimestamp() });
}

pub fn asciiByteCount(string: Str) usize {
    var c: usize = 0;
    for (string) |byte| {
        if (byte < 128)
            c += 1;
    }
    return c;
}

pub fn stripMarkupTags(mem: *std.mem.Allocator, string: Str) !Str {
    var buf = std.ArrayList(u8){ .len = string.len, .items = try std.mem.dupe(mem, u8, string), .allocator = mem };
    while (std.mem.indexOfScalar(u8, buf.items[0..buf.len], '<')) |idx_1| {
        if (std.mem.indexOfScalarPos(u8, buf.items[0..buf.len], idx_1, '>')) |idx_2|
            buf.len = zag.mem.edit(buf.items[0..buf.len], buf.len, idx_1, idx_2 + 1, "")
        else
            break;
    }
    return buf.toSliceConst();
}

pub fn utf8RuneCount(string: Str) !usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < string.len) {
        const byte_sequence_len = try std.unicode.utf8ByteSequenceLength(string[i]);
        i += byte_sequence_len;
        count += 1;
    }
    return count;
}
