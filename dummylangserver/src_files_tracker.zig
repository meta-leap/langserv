const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
const jsonic = @import("../../jsonic/jsonic.zig");
usingnamespace jsonic.Rpc;
usingnamespace @import("../langserv.zig");

pub var src_files_cache: std.StringHashMap(Str) = undefined;

pub fn cachedOrFreshSrc(mem: *std.mem.Allocator, src_file_uri: Str) ![]u8 {
    return if (src_files_cache.get(src_file_uri)) |in_cache|
        try std.mem.dupe(mem, u8, in_cache.value)
    else
        try std.fs.cwd().readFileAlloc(mem, zag.mem.trimPrefix(u8, src_file_uri, "file://"), std.math.maxInt(usize));
}

fn updateSrcInCache(mem: *std.mem.Allocator, src_file_uri: Str, src_full: ?Str) !void {
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

pub fn onFileBufSaved(ctx: Server.Ctx(DidSaveTextDocumentParams)) !void {
    try updateSrcInCache(&ctx.inst.mem_forever.?.allocator, ctx.value.textDocument.uri, ctx.value.text);
    try pushDiagnostics(ctx.mem, ctx.inst, ctx.value.textDocument.uri, null);

    const State = struct { token: ProgressToken, params: DidSaveTextDocumentParams };
    const token = ProgressToken{ .string = try zag.util.uniqueishId(ctx.mem, "dummylangserver_progress") };

    try ctx.inst.api.request(.@"window/workDoneProgress/create", State{
        .token = token,
        .params = ctx.value,
    }, WorkDoneProgressCreateParams{
        .token = token,
    }, struct {
        pub fn then(state: *State, resp: Server.Ctx(Result(void))) !void {
            switch (resp.value) {
                .err => |err| try resp.inst.api.notify(.@"window/showMessage", ShowMessageParams{
                    .@"type" = .Error,
                    .message = try std.fmt.allocPrint(resp.mem, "{}", .{err}),
                }),
                .ok => {
                    try resp.inst.api.notify(.@"$/progress", ProgressParams{ .token = state.token, .value = WorkDoneProgress{ .kind = "begin", .title = "Diags..", .percentage = 0 } });
                    var num_secs: usize = 5;
                    var sec: usize = 0;
                    while (sec < num_secs) : (sec += 1) {
                        std.time.sleep(1 * std.time.ns_per_s);
                        try resp.inst.api.notify(.@"$/progress", ProgressParams{ .token = state.token, .value = WorkDoneProgress{ .kind = "report", .title = "Diags..", .percentage = 10 + sec * (100 / num_secs), .message = try std.fmt.allocPrint(resp.mem, "{}/{}...", .{ sec + 1, num_secs }) } });
                    }
                    try resp.inst.api.notify(.@"$/progress", ProgressParams{ .token = state.token, .value = WorkDoneProgress{ .kind = "end", .title = "Diags..", .percentage = 100 } });
                    try pushDiagnostics(resp.mem, resp.inst, state.params.textDocument.uri, state.params.text);
                },
            }
        }
    });
}

fn pushDiagnostics(mem: *std.mem.Allocator, srv: *Server, src_file_uri: Str, src_full: ?Str) !void {
    var diags = try std.ArrayList(Diagnostic).initCapacity(mem, if (src_full == null) 0 else 8);
    if (src_full) |src| {
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, src, i, "file://")) |idx| {
            i = idx + "file://".len;
            try diags.append(Diagnostic{
                .range = try Range.initFromResliced(src, idx, i, false),
                .severity = .Warning,
                .message = "Local file path detected",
            });
        }
    }
    try srv.api.notify(.@"textDocument/publishDiagnostics", PublishDiagnosticsParams{
        .uri = src_file_uri,
        .diagnostics = diags.items[0..diags.len],
    });
}

pub fn onFileEvents(ctx: Server.Ctx(DidChangeWatchedFilesParams)) !void {
    for (ctx.value.changes) |change|
        try ctx.inst.api.notify(.@"window/showMessage", ShowMessageParams{
            .@"type" = .Info,
            .message = try std.fmt.allocPrint(ctx.mem, "{}", .{change}),
        });
}
