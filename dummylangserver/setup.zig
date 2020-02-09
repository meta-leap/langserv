const std = @import("std");
const zag = @import("../../zag/zag.zig");
const jsonic = @import("../../jsonic/jsonic.zig");
usingnamespace @import("../langserv.zig");
usingnamespace jsonic.Rpc;
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

    // HOVER TOOLTIP
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
    srv.precis.capabilities.renameProvider = .{ .options = .{ .prepareProvider = true } };
    srv.api.onRequest(.textDocument_rename, onRename);
    srv.api.onRequest(.textDocument_prepareRename, onRenamePrep);

    // SIGNATURE TOOLTIP
    srv.precis.capabilities.signatureHelpProvider = .{
        .triggerCharacters = ([_]String{ "[", "{" })[0..],
        .retriggerCharacters = ([_]String{ ",", ":" })[0..],
    };
    srv.api.onRequest(.textDocument_signatureHelp, onSignatureHelp);

    // SYMBOL HIGHLIGHT
    srv.precis.capabilities.documentHighlightProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_documentHighlight, onSymbolHighlight);

    // CODE ACTIONS / COMMANDS
    srv.precis.capabilities.codeActionProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_codeAction, onCodeActions);
    srv.precis.capabilities.executeCommandProvider = .{ .commands = ([_]String{ "dummylangserver.caseup", "dummylangserver.caselo" })[0..] };
    srv.api.onRequest(.workspace_executeCommand, onExecuteCommand);
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
    return TextEdit{ .range = ret_range, .newText = trimRight(src) };
}

fn trimRight(str: []const u8) []const u8 {
    return std.mem.trimRight(u8, str, "\t\r\n");
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

const RenameHelper = struct {
    src: []const u8,
    word_start: usize,
    word_end: usize,
    full_src_range: Range,

    fn init(mem: *std.mem.Allocator, src_file_uri: []const u8, position: Position) !?RenameHelper {
        var ret: RenameHelper = undefined;
        ret.src = if (utils.src_files_cache.?.get(src_file_uri)) |in_cache|
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

fn onRename(ctx: Server.Ctx(RenameParams)) !Result(?WorkspaceEdit) {
    const src_file_uri = ctx.value.TextDocumentPositionParams.textDocument.uri;
    if (try RenameHelper.init(ctx.mem, src_file_uri, ctx.value.TextDocumentPositionParams.position)) |ren| {
        const new_src = try zag.mem.replace(u8, ctx.mem, ren.src, ren.src[ren.word_start..ren.word_end], ctx.value.newName);

        var edits = try ctx.mem.alloc(TextEdit, 1);
        edits[0] = .{ .newText = trimRight(new_src), .range = ren.full_src_range };
        var ret = WorkspaceEdit{ .changes = std.StringHashMap([]TextEdit).init(ctx.mem) };
        _ = try ret.changes.?.put(src_file_uri, edits);

        return Result(?WorkspaceEdit){ .ok = ret };
    }
    return Result(?WorkspaceEdit){ .ok = null };
}

fn onRenamePrep(ctx: Server.Ctx(TextDocumentPositionParams)) !Result(?RenamePrep) {
    const src_file_uri = ctx.value.textDocument.uri;
    if (try RenameHelper.init(ctx.mem, src_file_uri, ctx.value.position)) |ren|
        if (try Position.fromByteIndexIn(ren.src, ren.word_start)) |pos_start|
            if (try Position.fromByteIndexIn(ren.src, ren.word_end)) |pos_end| {
                return Result(?RenamePrep){
                    .ok = .{
                        .augmented = .{
                            .placeholder = "Hint text goes here.",
                            .range = .{ .start = pos_start, .end = pos_end },
                        },
                    },
                };
            };
    return Result(?RenamePrep){ .ok = null };
}

fn onSignatureHelp(ctx: Server.Ctx(SignatureHelpParams)) !Result(?SignatureHelp) {
    var sigs = try ctx.mem.alloc(SignatureInformation, 3);
    for (sigs) |_, i| {
        sigs[i].label = try std.fmt.allocPrint(ctx.mem, "Signature {} label", .{i});
        sigs[i].documentation = MarkupContent{ .value = try std.fmt.allocPrint(ctx.mem, "Signature **{}** markdown with `bells` & *whistles*..", .{i}) };
        sigs[i].parameters = try ctx.mem.alloc(ParameterInformation, 2);
        sigs[i].parameters.?[0].label = try std.fmt.allocPrint(ctx.mem, "Signature {}, param 0 label", .{i});
        sigs[i].parameters.?[0].documentation = MarkupContent{ .value = try std.fmt.allocPrint(ctx.mem, "Signature **{}**, param 0 markdown with `bells` & *whistles*..", .{i}) };
        sigs[i].parameters.?[1].label = try std.fmt.allocPrint(ctx.mem, "Signature {}, param 1 label", .{i});
        sigs[i].parameters.?[1].documentation = MarkupContent{ .value = try std.fmt.allocPrint(ctx.mem, "Signature **{}**, param 1 markdown with `bells` & *whistles*..", .{i}) };
    }
    return Result(?SignatureHelp){ .ok = .{ .signatures = sigs } };
}

fn onSymbolHighlight(ctx: Server.Ctx(DocumentHighlightParams)) !Result(?[]DocumentHighlight) {
    const src_file_uri = ctx.value.TextDocumentPositionParams.textDocument.uri;
    if (try RenameHelper.init(ctx.mem, src_file_uri, ctx.value.TextDocumentPositionParams.position)) |ren| {
        const word = ren.src[ren.word_start..ren.word_end];
        var syms = try std.ArrayList(DocumentHighlight).initCapacity(ctx.mem, 8);
        var i: usize = 0;
        while (i < ren.src.len) {
            if (std.mem.indexOfPos(u8, ren.src, i, word)) |idx| {
                i = idx + word.len;
                try syms.append(.{
                    .range = .{
                        .start = (try Position.fromByteIndexIn(ren.src, idx)) orelse continue,
                        .end = (try Position.fromByteIndexIn(ren.src, i)) orelse continue,
                    },
                });
            } else
                break;
        }
        return Result(?[]DocumentHighlight){ .ok = syms.items[0..syms.len] };
    }
    return Result(?[]DocumentHighlight){ .ok = null };
}

fn onCodeActions(ctx: Server.Ctx(CodeActionParams)) !Result(?[]CommandOrAction) {
    var ret = try ctx.mem.alloc(CommandOrAction, 2);
    var args = try ctx.mem.alloc(jsonic.AnyValue, 1);
    args[0] = .{ .string = ctx.value.textDocument.uri };
    ret[0] = .{ .command_only = .{ .title = "Uppercase all a-z", .command = "dummylangserver.caseup", .arguments = args } };
    ret[1] = .{ .command_only = .{ .title = "Lowercase all A-Z", .command = "dummylangserver.caselo", .arguments = args } };
    return Result(?[]CommandOrAction){ .ok = ret };
}

fn onExecuteCommand(ctx: Server.Ctx(ExecuteCommandParams)) !Result(?jsonic.AnyValue) {
    if (ctx.value.arguments) |args|
        if (args.len == 1) switch (args[0]) {
            else => {},
            .string => |src_file_uri| {
                const is_to_upper = std.mem.eql(u8, ctx.value.command, "dummylangserver.caseup");
                const is_to_lower = std.mem.eql(u8, ctx.value.command, "dummylangserver.caselo");
                if (is_to_upper or is_to_lower) {
                    var src = if (utils.src_files_cache.?.get(src_file_uri)) |in_cache|
                        try std.mem.dupe(ctx.mem, u8, in_cache.value)
                    else
                        try std.fs.cwd().readFileAlloc(ctx.mem, zag.mem.trimPrefix(u8, src_file_uri, "file://"), std.math.maxInt(usize));
                    if (try Range.initFrom(src)) |full_src_range| {
                        for (src) |char, i| {
                            if (is_to_lower and char >= 'A' and char <= 'Z')
                                src[i] = char + 32
                            else if (is_to_upper and char >= 'a' and char <= 'z')
                                src[i] = char - 32;
                        }

                        var edits = try ctx.mem.alloc(TextEdit, 1);
                        edits[0] = .{ .newText = trimRight(src), .range = full_src_range };
                        var edit = WorkspaceEdit{ .changes = std.StringHashMap([]TextEdit).init(ctx.mem) };
                        _ = try edit.changes.?.put(src_file_uri, edits);

                        try ctx.inst.api.request(.workspace_applyEdit, {}, ApplyWorkspaceEditParams{ .edit = edit }, struct {
                            pub fn then(state: void, resp: Server.Ctx(Result(ApplyWorkspaceEditResponse))) error{}!void {
                                switch (resp.value) {
                                    .err => |err| std.debug.warn("Requested edit not applied by client: {}\n", .{err}),
                                    .ok => |outcome| if (!outcome.applied)
                                        if (outcome.failureReason) |err|
                                            std.debug.warn("Requested edit not applied by client: {}\n", .{err}),
                                }
                            }
                        });

                        return Result(?jsonic.AnyValue){ .ok = null };
                    }
                }
            },
        };
    return fail(?jsonic.AnyValue);
}
