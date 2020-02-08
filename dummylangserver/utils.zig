const std = @import("std");
usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").Rpc;

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
