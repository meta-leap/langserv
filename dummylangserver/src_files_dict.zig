const std = @import("std");
usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").Rpc;

pub var cache: ?std.StringHashMap(String) = null;

pub fn onFileBufOpened(ctx: Server.Ctx(DidOpenTextDocumentParams)) !void {
    const srv = ctx.inst;
    if (try cache.?.put(
        try std.mem.dupe(&srv.mem_forever.?.allocator, u8, ctx.value.textDocument.uri),
        try std.mem.dupe(&srv.mem_forever.?.allocator, u8, ctx.value.textDocument.text),
    )) |old_src| {
        srv.mem_forever.?.allocator.free(old_src.key);
        srv.mem_forever.?.allocator.free(old_src.value);
    }
}

pub fn onFileBufEdited(ctx: Server.Ctx(DidChangeTextDocumentParams)) error{}!void {
    if (ctx.value.contentChanges.len > 0) {
        //
    }
    std.debug.warn("onFileBufEdited:\turi={s} num_deltas={}\n", .{
        ctx.value.textDocument.TextDocumentIdentifier.uri,
        ctx.value.contentChanges.len,
    });
}
