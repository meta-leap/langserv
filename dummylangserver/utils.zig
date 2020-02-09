const std = @import("std");
const zag = @import("../../zag/zag.zig");
usingnamespace @import("../langserv.zig");
usingnamespace @import("../../jsonic/jsonic.zig").Rpc;

pub var src_files_cache: ?std.StringHashMap(String) = null;

fn updateSrcInCache(srv: *Server, uri: String, src_full: ?String) !void {
    const mem = &srv.mem_forever.?.allocator;
    const old = if (src_full) |src|
        try src_files_cache.?.put(try std.mem.dupe(mem, u8, uri), try std.mem.dupe(mem, u8, src))
    else
        src_files_cache.?.remove(uri);
    if (old) |old_src| {
        mem.free(old_src.key);
        mem.free(old_src.value);
    }
}

pub fn onFileBufOpened(ctx: Server.Ctx(DidOpenTextDocumentParams)) !void {
    try updateSrcInCache(ctx.inst, ctx.value.textDocument.uri, ctx.value.textDocument.text);
}

pub fn onFileClosed(ctx: Server.Ctx(DidCloseTextDocumentParams)) !void {
    try updateSrcInCache(ctx.inst, ctx.value.textDocument.uri, null);
}

pub fn onFileBufEdited(ctx: Server.Ctx(DidChangeTextDocumentParams)) !void {
    if (ctx.value.contentChanges.len > 0) {
        std.debug.assert(ctx.value.contentChanges.len == 1);
        try updateSrcInCache(ctx.inst, ctx.value.textDocument.
            TextDocumentIdentifier.uri, ctx.value.contentChanges[0].text);
    }
}

pub fn fail(comptime T: type) Result(T) {
    return Result(T){ .err = .{ .code = 12121, .message = "somewhere there's a bug in here." } };
}

pub fn trimRight(str: []const u8) []const u8 {
    return std.mem.trimRight(u8, str, " \t\r\n");
}

pub fn format(src_file_uri: String, src_range: ?Range, mem: *std.mem.Allocator) !?TextEdit {
    var src = if (src_files_cache.?.get(src_file_uri)) |in_cache|
        try std.mem.dupe(mem, u8, in_cache.value)
    else
        try std.fs.cwd().readFileAlloc(mem, zag.mem.trimPrefix(u8, src_file_uri, "file://"), std.math.maxInt(usize));

    var ret_range: Range = undefined;
    if (src_range) |range| {
        ret_range = range;
        src = (try range.slice(src)) orelse return null;
    } else
        ret_range = (try Range.initFrom(src)) orelse return null;

    for (src) |char, i| {
        if (char == ' ')
            src[i] = '\t'
        else if (char == '\t')
            src[i] = ' ';
    }
    return TextEdit{ .range = ret_range, .newText = src };
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
        ret.src = if (src_files_cache.?.get(src_file_uri)) |in_cache|
            try std.mem.dupe(mem, u8, in_cache.value)
        else
            try std.fs.cwd().readFileAlloc(mem, zag.mem.trimPrefix(u8, src_file_uri, "file://"), std.math.maxInt(usize));

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
