const std = @import("std");
const zag = @import("../../zag/zag.zig");
usingnamespace @import("../langserv.zig");

pub var src_files_cache: std.StringHashMap(String) = undefined;

pub fn cachedOrFreshSrc(mem: *std.mem.Allocator, src_file_uri: String) ![]u8 {
    return if (src_files_cache.get(src_file_uri)) |in_cache|
        try std.mem.dupe(mem, u8, in_cache.value)
    else
        try std.fs.cwd().readFileAlloc(mem, zag.mem.trimPrefix(u8, src_file_uri, "file://"), std.math.maxInt(usize));
}

fn updateSrcInCache(mem: *std.mem.Allocator, src_file_uri: String, src_full: ?String) !void {
    const old = if (src_full) |src|
        try src_files_cache.put(try std.mem.dupe(mem, u8, src_file_uri), try std.mem.dupe(mem, u8, src))
    else
        src_files_cache.remove(src_file_uri);
    if (old) |old_src| {
        mem.free(old_src.key);
        mem.free(old_src.value);
    }
}

pub fn onFileBufOpened(ctx: Server.Ctx(DidOpenTextDocumentParams)) !void {
    try updateSrcInCache(&ctx.inst.mem_forever.?.allocator, ctx.value.textDocument.uri, ctx.value.textDocument.text);
    try pushDiagnostics(ctx.mem, ctx.inst, ctx.value.textDocument.uri, ctx.value.textDocument.text);
}

pub fn onFileClosed(ctx: Server.Ctx(DidCloseTextDocumentParams)) !void {
    try updateSrcInCache(&ctx.inst.mem_forever.?.allocator, ctx.value.textDocument.uri, null);
    try pushDiagnostics(ctx.mem, ctx.inst, ctx.value.textDocument.uri, null);
}

pub fn onFileBufEdited(ctx: Server.Ctx(DidChangeTextDocumentParams)) !void {
    if (ctx.value.contentChanges.len > 0) {
        std.debug.assert(ctx.value.contentChanges.len == 1);
        try updateSrcInCache(&ctx.inst.mem_forever.?.allocator, ctx.value.textDocument.
            TextDocumentIdentifier.uri, ctx.value.contentChanges[0].text);
        try pushDiagnostics(ctx.mem, ctx.inst, ctx.value.textDocument.TextDocumentIdentifier.uri, ctx.value.contentChanges[0].text);
    }
}

fn pushDiagnostics(mem: *std.mem.Allocator, srv: *Server, src_file_uri: String, src_full: ?String) !void {
    var diags = try std.ArrayList(Diagnostic).initCapacity(mem, if (src_full == null) 0 else 8);
    if (src_full) |src| {
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, src, i, "file://")) |idx| {
            i = idx + "file://".len;
            if (try Range.initFromSlice(src, idx, i)) |range|
                try diags.append(Diagnostic{
                    .range = range,
                    .severity = .Warning,
                    .message = "Local file path detected",
                });
        }
    }
    try srv.api.notify(.textDocument_publishDiagnostics, PublishDiagnosticsParams{
        .uri = src_file_uri,
        .diagnostics = diags.items[0..diags.len],
    });
}
