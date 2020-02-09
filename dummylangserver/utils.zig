const std = @import("std");
const zag = @import("../../zag/zag.zig");
usingnamespace @import("../langserv.zig");
usingnamespace @import("../../jsonic/jsonic.zig").Rpc;
usingnamespace @import("./src_files_tracker.zig");

pub fn fail(comptime T: type) Result(T) {
    return Result(T){ .err = .{ .code = 12121, .message = "somewhere there's a bug in here." } };
}

pub fn trimRight(str: []const u8) []const u8 {
    return std.mem.trimRight(u8, str, " \t\r\n");
}

pub fn gatherPseudoNameLocations(mem: *std.mem.Allocator, src_file_uri: String, pos: Position) !?[]Range {
    if (try PseudoNameHelper.init(mem, src_file_uri, pos)) |name_helper| {
        const word = name_helper.src[name_helper.word_start..name_helper.word_end];
        var locs = try std.ArrayList(Range).initCapacity(mem, 8);
        var i: usize = 0;
        while (i < name_helper.src.len) {
            if (std.mem.indexOfPos(u8, name_helper.src, i, word)) |idx| {
                i = idx + word.len;
                try locs.append((try Range.initFromSlice(name_helper.src, idx, i)) orelse continue);
            } else
                break;
        }
        return locs.items[0..locs.len];
    }
    return null;
}

pub const PseudoNameHelper = struct {
    src: []const u8,
    word_start: usize,
    word_end: usize,
    full_src_range: Range,

    pub fn init(mem: *std.mem.Allocator, src_file_uri: []const u8, position: Position) !?PseudoNameHelper {
        var ret: PseudoNameHelper = undefined;
        ret.src = try cachedOrFreshSrc(mem, src_file_uri);

        if (try Range.initFrom(ret.src)) |*range| {
            ret.full_src_range = range.*;
            if (try position.toByteIndexIn(ret.src)) |pos|
                if ((ret.src[pos] >= 'a' and ret.src[pos] <= 'z') or (ret.src[pos] >= 'A' and ret.src[pos] <= 'Z')) {
                    ret.word_start = pos;
                    ret.word_end = pos;
                    while (ret.word_end < ret.src.len and ((ret.src[ret.word_end] >= 'a' and ret.src[ret.word_end] <= 'z') or (ret.src[ret.word_end] >= 'A' and ret.src[ret.word_end] <= 'Z')))
                        ret.word_end += 1;
                    while (ret.word_start >= 0 and ((ret.src[ret.word_start] >= 'a' and ret.src[ret.word_start] <= 'z') or (ret.src[ret.word_start] >= 'A' and ret.src[ret.word_start] <= 'Z')))
                        ret.word_start -= 1;
                    ret.word_start += 1;

                    if (ret.word_start < ret.word_end)
                        return ret;
                };
        }
        return null;
    }
};
