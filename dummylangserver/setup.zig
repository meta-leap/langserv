const std = @import("std");
const zag = @import("../../zag/api.zig");
usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").Rpc;
const src_sync = @import("./src_files_dict.zig");

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);

    // FILE EVENTS
    srv.precis.capabilities.textDocumentSync = .{
        .options = .{
            .openClose = true,
            .change = TextDocumentSyncKind.Full,
        },
    };
    srv.api.onNotify(.textDocument_didClose, src_sync.onFileClosed);
    srv.api.onNotify(.textDocument_didOpen, src_sync.onFileBufOpened);
    srv.api.onNotify(.textDocument_didChange, src_sync.onFileBufEdited);

    // HOVER
    srv.precis.capabilities.hoverProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_hover, onHover);

    // AUTO-COMPLETE
    srv.precis.capabilities.completionProvider = .{
        .triggerCharacters = &[_]String{"."},
        .allCommitCharacters = &[_]String{"\t"},
        .resolveProvider = true,
    };
    srv.api.onRequest(.textDocument_completion, onCompletion);
    srv.api.onRequest(.completionItem_resolve, onCompletionResolve);

    // FMT
    srv.precis.capabilities.documentRangeFormattingProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_rangeFormatting, onFormatting);
}

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    src_sync.cache = std.StringHashMap(String).init(&ctx.inst.mem_forever.?.allocator);
    std.debug.warn("\nINIT\t{}\n", .{ctx.value});
    try ctx.inst.api.notify(.window_showMessage, ShowMessageParams{
        .type__ = .Warning,
        .message = try std.fmt.allocPrint(ctx.mem, "So it's you... {} {}.", .{
            ctx.inst.initialized.?.clientInfo.?.name,
            ctx.inst.initialized.?.clientInfo.?.version,
        }),
    });
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    src_sync.cache.?.deinit();
    return Result(void){ .ok = {} };
}

fn onHover(ctx: Server.Ctx(HoverParams)) !Result(?Hover) {
    const static = struct {
        var last_pos = Position{ .line = 0, .character = 0 };
    };
    const last_pos = static.last_pos;
    static.last_pos = ctx.value.TextDocumentPositionParams.position;
    const markdown = try std.fmt.allocPrint(ctx.mem, "Hover request:\n\n```\n{}\n```\n", .{ctx.
        value.TextDocumentPositionParams.textDocument.uri});
    return Result(?Hover){
        .ok = Hover{
            .contents = MarkupContent{ .value = markdown },
            .range = .{ .start = last_pos, .end = static.last_pos },
        },
    };
}

fn onCompletion(ctx: Server.Ctx(CompletionParams)) !Result(?CompletionList) {
    var cmpls = try std.ArrayList(CompletionItem).initCapacity(ctx.mem, 8);
    try cmpls.append(CompletionItem{ .label = @typeName(CompletionItemKind) ++ " members:", .sortText = "000" });
    inline for (@typeInfo(CompletionItemKind).Enum.fields) |*enum_field| {
        var item = CompletionItem{
            .label = try std.fmt.allocPrint(ctx.mem, "\t.{s} =\t{d}", .{ enum_field.name, enum_field.value }),
            .kind = @intToEnum(CompletionItemKind, enum_field.value),
            .sortText = try std.fmt.allocPrint(ctx.mem, "{:0>3}", .{enum_field.value}),
            .insertText = enum_field.name,
        };
        try cmpls.append(item);
    }
    return Result(?CompletionList){ .ok = .{ .items = cmpls.items[0..cmpls.len] } };
}

fn onCompletionResolve(ctx: Server.Ctx(CompletionItem)) !Result(CompletionItem) {
    var item = ctx.value;
    item.detail = item.sortText;
    if (item.insertText) |insert_text|
        item.documentation = .{ .value = try std.fmt.allocPrint(ctx.mem, "Above is current `" ++ @typeName(CompletionItemKind) ++ ".sortText`, and its `.insertText` is: `\"{s}\"`.", .{insert_text}) };
    return Result(CompletionItem){ .ok = item };
}

fn onFormatting(ctx: Server.Ctx(DocumentRangeFormattingParams)) !Result(?[]TextEdit) {
    var src = if (src_sync.cache.?.get(ctx.value.textDocument.uri)) |in_cache|
        try std.mem.dupe(ctx.mem, u8, in_cache.value)
    else
        try std.fs.cwd().readFileAlloc(
            ctx.mem,
            zag.mem.trimPrefix(u8, ctx.value.textDocument.uri, "file://"),
            std.math.maxInt(usize),
        );

    var sub_src = (try ctx.value.range.slice(src)) orelse
        return Result(?[]TextEdit){ .err = .{ .code = 12121, .message = "somewhere there's a bug in here.." } };

    for (sub_src) |char, i| {
        if (char == ' ')
            sub_src[i] = '\t'
        else if (char == '\t')
            sub_src[i] = ' ';
    }

    const edits = try ctx.mem.alloc(TextEdit, 1);
    edits[0] = TextEdit{ .range = ctx.value.range, .newText = sub_src };
    return Result(?[]TextEdit){ .ok = edits };
}
