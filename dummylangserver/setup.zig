const std = @import("std");
const zag = @import("../../zag/api.zig");
usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").Rpc;
const utils = @import("./utils.zig");

fn fail(comptime T: type) Result(T) {
    return Result(T){ .err = .{ .code = 12121, .message = "somewhere there's a bug in here." } };
}

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
    srv.api.onNotify(.textDocument_didClose, utils.onFileClosed);
    srv.api.onNotify(.textDocument_didOpen, utils.onFileBufOpened);
    srv.api.onNotify(.textDocument_didChange, utils.onFileBufEdited);

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

    // FORMATTING
    srv.precis.capabilities.documentRangeFormattingProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_rangeFormatting, onFormatRange);
    srv.precis.capabilities.documentOnTypeFormattingProvider = .{ .firstTriggerCharacter = "}" };
    srv.api.onRequest(.textDocument_onTypeFormatting, onFormatOnType);

    // SYMBOLS
    srv.precis.capabilities.documentSymbolProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_documentSymbol, onSymbols);

    // RENAME
    srv.precis.capabilities.renameProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_rename, onRename);
}

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    utils.src_files_cache = std.StringHashMap(String).init(&ctx.inst.mem_forever.?.allocator);
    std.debug.warn("\nINIT\t{}\n", .{ctx.value});
    try ctx.inst.api.notify(.window_showMessage, ShowMessageParams{
        .@"type" = .Warning,
        .message = try std.fmt.allocPrint(ctx.mem, "So it's you... {} {}.", .{
            ctx.inst.initialized.?.clientInfo.?.name,
            ctx.inst.initialized.?.clientInfo.?.version,
        }),
    });
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    utils.src_files_cache.?.deinit();
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

fn onFormatRange(ctx: Server.Ctx(DocumentRangeFormattingParams)) !Result(?[]TextEdit) {
    const edit = (try doFormat(ctx.value.textDocument.uri, ctx.value.range, ctx.mem)) orelse
        return fail(?[]TextEdit);
    const edits = try ctx.mem.alloc(TextEdit, 1);
    edits[0] = edit;
    return Result(?[]TextEdit){ .ok = edits };
}

fn onFormatOnType(ctx: Server.Ctx(DocumentOnTypeFormattingParams)) !Result(?[]TextEdit) {
    var edit = (try doFormat(ctx.value.TextDocumentPositionParams.textDocument.uri, null, ctx.mem)) orelse
        return fail(?[]TextEdit);
    const edits = try ctx.mem.alloc(TextEdit, 1);
    edits[0] = edit;
    return Result(?[]TextEdit){ .ok = edits };
}

fn doFormat(src_file_uri: String, src_range: ?Range, mem: *std.mem.Allocator) !?TextEdit {
    var src = if (utils.src_files_cache.?.get(src_file_uri)) |in_cache|
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
    return TextEdit{ .range = ret_range, .newText = std.mem.trimRight(u8, src, " \t\r\n") };
}

fn onSymbols(ctx: Server.Ctx(DocumentSymbolParams)) !Result(?DocumentSymbols) {
    var symbols = try ctx.mem.alloc(DocumentSymbol, @typeInfo(SymbolKind).Enum.fields.len);
    comptime var i: usize = 0;
    inline for (@typeInfo(SymbolKind).Enum.fields) |*enum_field| {
        symbols[i] = DocumentSymbol{
            .name = enum_field.name,
            .detail = try std.fmt.allocPrint(ctx.mem, "{s}.{s} = {d}", .{ @typeName(SymbolKind), enum_field.name, enum_field.value }),
            .kind = @intToEnum(SymbolKind, enum_field.value),
            .range = Range{ .start = .{ .character = 0, .line = i }, .end = .{ .character = 22, .line = i } },
            .selectionRange = Range{ .start = .{ .character = 0, .line = i }, .end = .{ .character = 22, .line = i } },
        };
        i += 1;
    }
    return Result(?DocumentSymbols){ .ok = .{ .hierarchy = symbols } };
}

fn onRename(ctx: Server.Ctx(RenameParams)) !Result(?WorkspaceEdit) {
    const src_file_uri = ctx.value.TextDocumentPositionParams.textDocument.uri;
    var src = if (utils.src_files_cache.?.get(src_file_uri)) |in_cache|
        try std.mem.dupe(ctx.mem, u8, in_cache.value)
    else
        try std.fs.cwd().readFileAlloc(ctx.mem, zag.mem.trimPrefix(u8, src_file_uri, "file://"), std.math.maxInt(usize));

    if (try Range.initFrom(src)) |range|
        if (try ctx.value.TextDocumentPositionParams.position.toByteIndexIn(src)) |pos|
            if ((src[pos] >= 'a' and src[pos] <= 'z') or (src[pos] >= 'A' and src[pos] <= 'Z')) {
                var pos_start = pos;
                var pos_end = pos;
                while (pos_end < src.len and ((src[pos_end] >= 'a' and src[pos_end] <= 'z') or (src[pos_end] >= 'A' and src[pos_end] <= 'Z')))
                    pos_end += 1;
                while (pos_start >= 0 and ((src[pos_start] >= 'a' and src[pos_start] <= 'z') or (src[pos_start] >= 'A' and src[pos_start] <= 'Z')))
                    pos_start -= 1;
                pos_start += 1;

                const word = src[pos_start..pos_end];
                const new_src = try zag.mem.replace(u8, src, word, ctx.value.newName, ctx.mem);

                var edits = try ctx.mem.alloc(TextEdit, 1);
                edits[0] = .{ .newText = new_src, .range = range };
                var ret = WorkspaceEdit{ .changes = std.StringHashMap([]TextEdit).init(ctx.mem) };
                _ = try ret.changes.?.put(src_file_uri, edits);

                return Result(?WorkspaceEdit){ .ok = ret };
            };

    return fail(?WorkspaceEdit);
}
