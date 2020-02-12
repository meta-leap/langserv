const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
const jsonic = @import("../../jsonic/jsonic.zig");
usingnamespace @import("../langserv.zig");
usingnamespace jsonic.Rpc;
usingnamespace @import("./src_files_tracker.zig");
const utils = @import("./utils.zig");

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);

    // FILE EVENTS
    srv.cfg.capabilities.textDocumentSync = .{
        .options = .{
            .openClose = true,
            .change = TextDocumentSyncKind.Full,
            .save = .{ .includeText = true },
        },
    };
    srv.api.onNotify(.textDocument_didClose, onFileClosed);
    srv.api.onNotify(.textDocument_didOpen, onFileBufOpened);
    srv.api.onNotify(.textDocument_didChange, onFileBufEdited);
    srv.api.onNotify(.textDocument_didSave, onFileBufSaved);
    srv.api.onNotify(.workspace_didChangeWatchedFiles, onFileEvents);

    // HOVER TOOLTIP
    srv.cfg.capabilities.hoverProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_hover, onHover);

    // AUTO-COMPLETE
    srv.cfg.capabilities.completionProvider = .{
        .triggerCharacters = &[_]Str{"."},
        .allCommitCharacters = &[_]Str{"\t"},
        .resolveProvider = true,
    };
    srv.api.onRequest(.textDocument_completion, onCompletion);
    srv.api.onRequest(.completionItem_resolve, onCompletionResolve);

    // FORMATTING
    srv.cfg.capabilities.documentRangeFormattingProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_rangeFormatting, onFormatRange);
    srv.cfg.capabilities.documentOnTypeFormattingProvider = .{ .firstTriggerCharacter = "}" };
    srv.api.onRequest(.textDocument_onTypeFormatting, onFormatOnType);

    // SYMBOLS
    srv.cfg.capabilities.documentSymbolProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_documentSymbol, onSymbols);

    // RENAME
    srv.cfg.capabilities.renameProvider = .{ .options = .{ .prepareProvider = true } };
    srv.api.onRequest(.textDocument_prepareRename, onRenamePrep);
    srv.api.onRequest(.textDocument_rename, onRename);

    // SIGNATURE TOOLTIP
    srv.cfg.capabilities.signatureHelpProvider = .{
        .triggerCharacters = &[_]Str{ "[", "{" },
        .retriggerCharacters = &[_]Str{ ",", ":" },
    };
    srv.api.onRequest(.textDocument_signatureHelp, onSignatureHelp);

    // SYMBOL HIGHLIGHT
    srv.cfg.capabilities.documentHighlightProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_documentHighlight, onSymbolHighlight);

    // CODE ACTIONS / COMMANDS
    srv.cfg.capabilities.codeActionProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_codeAction, onCodeActions);
    srv.cfg.capabilities.executeCommandProvider = .{
        .commands = &[_]Str{
            "dummylangserver.caseup",
            "dummylangserver.caselo",
            "dummylangserver.infomsg",
        },
    };
    srv.api.onRequest(.workspace_executeCommand, onExecuteCommand);
    srv.cfg.capabilities.codeLensProvider = .{ .resolveProvider = false };
    srv.api.onRequest(.textDocument_codeLens, onCodeLenses);

    // SELECTION RANGE
    srv.cfg.capabilities.selectionRangeProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_selectionRange, onSelectionRange);

    // CODE LOCATIONS
    srv.cfg.capabilities.referencesProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_references, Locs(ReferenceParams, []Location).handle);
    srv.cfg.capabilities.definitionProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_definition, Locs(DefinitionParams, Locations).handle);
    srv.cfg.capabilities.typeDefinitionProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_typeDefinition, Locs(TypeDefinitionParams, Locations).handle);
    srv.cfg.capabilities.declarationProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_declaration, Locs(DeclarationParams, Locations).handle);
    srv.cfg.capabilities.implementationProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_implementation, Locs(ImplementationParams, Locations).handle);
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
    return onFormat(ctx.mem, ctx.value.textDocument.uri, ctx.value.range);
}

fn onFormatOnType(ctx: Server.Ctx(DocumentOnTypeFormattingParams)) !Result(?[]TextEdit) {
    return onFormat(ctx.mem, ctx.value.TextDocumentPositionParams.textDocument.uri, null);
}

fn onFormat(mem: *std.mem.Allocator, src_file_uri: Str, src_range: ?Range) !Result(?[]TextEdit) {
    var src = try cachedOrFreshSrc(mem, src_file_uri);

    var ret_range: Range = undefined;
    if (src_range) |range| {
        ret_range = range;
        src = (try range.slice(src)) orelse return Result(?[]TextEdit){ .ok = null };
    } else
        ret_range = (try Range.initFrom(src)) orelse return Result(?[]TextEdit){ .ok = null };

    for (src) |char, i| {
        if (char == ' ')
            src[i] = '\t'
        else if (char == '\t')
            src[i] = ' ';
    }

    const edits = try mem.alloc(TextEdit, 1);
    edits[0] = TextEdit{ .range = ret_range, .newText = src };
    return Result(?[]TextEdit){ .ok = edits };
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
    if (try utils.PseudoNameHelper.init(ctx.mem, src_file_uri, ctx.value.TextDocumentPositionParams.position)) |name_helper| {
        const new_src = try zag.mem.replace(u8, ctx.mem, name_helper.src, name_helper.src[name_helper.word_start..name_helper.word_end], ctx.value.newName);

        var edits = try ctx.mem.alloc(TextEdit, 1);
        edits[0] = .{ .newText = utils.trimRight(new_src), .range = name_helper.full_src_range };
        var ret = WorkspaceEdit{ .changes = std.StringHashMap([]TextEdit).init(ctx.mem) };
        _ = try ret.changes.?.put(src_file_uri, edits);

        return Result(?WorkspaceEdit){ .ok = ret };
    }
    return Result(?WorkspaceEdit){ .ok = null };
}

fn onRenamePrep(ctx: Server.Ctx(TextDocumentPositionParams)) !Result(?RenamePrep) {
    const src_file_uri = ctx.value.textDocument.uri;
    if (try utils.PseudoNameHelper.init(ctx.mem, src_file_uri, ctx.value.position)) |name_helper|
        if (try Range.initFromSlice(name_helper.src, name_helper.word_start, name_helper.word_end)) |range| {
            return Result(?RenamePrep){ .ok = .{ .augmented = .{ .placeholder = "Hint text goes here.", .range = range } } };
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
    if (try utils.gatherPseudoNameLocations(ctx.mem, src_file_uri, ctx.value.TextDocumentPositionParams.position)) |ranges| {
        var syms = try ctx.mem.alloc(DocumentHighlight, ranges.len);
        for (syms) |_, i| {
            syms[i].kind = .Text;
            syms[i].range = ranges[i];
        }
        return Result(?[]DocumentHighlight){ .ok = syms };
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
            .string => |arg| if (std.mem.eql(u8, ctx.value.command, "dummylangserver.infomsg")) {
                try ctx.inst.api.notify(.window_showMessage, ShowMessageParams{ .@"type" = .Info, .message = arg });
                return Result(?jsonic.AnyValue){ .ok = null };
            } else {
                const src_file_uri = arg;
                const is_to_upper = std.mem.eql(u8, ctx.value.command, "dummylangserver.caseup");
                const is_to_lower = std.mem.eql(u8, ctx.value.command, "dummylangserver.caselo");
                if (is_to_upper or is_to_lower) {
                    var src = try cachedOrFreshSrc(ctx.mem, src_file_uri);
                    if (try Range.initFrom(src)) |full_src_range| {
                        for (src) |char, i| {
                            if (is_to_lower and char >= 'A' and char <= 'Z')
                                src[i] = char + 32
                            else if (is_to_upper and char >= 'a' and char <= 'z')
                                src[i] = char - 32;
                        }

                        var edits = try ctx.mem.alloc(TextEdit, 1);
                        edits[0] = .{ .newText = utils.trimRight(src), .range = full_src_range };
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
    return utils.fail(?jsonic.AnyValue);
}

fn onCodeLenses(ctx: Server.Ctx(CodeLensParams)) !Result(?[]CodeLens) {
    var lenses = try ctx.mem.alloc(CodeLens, 3);
    for (lenses) |_, i| {
        lenses[i].range = .{ .start = .{ .line = 2 + 2 * @intCast(isize, i), .character = 6 }, .end = .{ .line = 2 + 2 * @intCast(isize, i), .character = 42 } };
        lenses[i].command = .{
            .title = try std.fmt.allocPrint(ctx.mem, "Codelens #{d}", .{i}),
            .command = "dummylangserver.infomsg",
            .arguments = try ctx.mem.alloc(jsonic.AnyValue, 1),
        };
        lenses[i].command.?.arguments.?[0] = .{
            .string = try std.fmt.allocPrint(ctx.mem, "This is the info message for codelens #{d}", .{i}),
        };
    }
    return Result(?[]CodeLens){ .ok = lenses };
}

fn onSelectionRange(ctx: Server.Ctx(SelectionRangeParams)) !Result(?[]SelectionRange) {
    const src_file_uri = ctx.value.textDocument.uri;
    var ranges = try ctx.mem.alloc(SelectionRange, ctx.value.positions.len);
    for (ctx.value.positions) |pos, i| {
        ranges[i].parent = null;
        if (try utils.PseudoNameHelper.init(ctx.mem, src_file_uri, pos)) |name_helper|
            ranges[i].range = (try Range.initFromSlice(name_helper.src, name_helper.word_start, name_helper.word_end)) orelse
                return Result(?[]SelectionRange){ .ok = null }
        else
            return Result(?[]SelectionRange){ .ok = null };
    }
    return Result(?[]SelectionRange){ .ok = ranges };
}

fn Locs(comptime TArg: type, comptime TRet: type) type {
    return struct {
        fn handle(ctx: Server.Ctx(TArg)) !Result(?TRet) {
            const src_file_uri = ctx.value.TextDocumentPositionParams.textDocument.uri;
            if (try utils.gatherPseudoNameLocations(ctx.mem, src_file_uri, ctx.value.TextDocumentPositionParams.position)) |ranges| {
                var locs = try ctx.mem.alloc(Location, ranges.len);
                for (locs) |_, i| {
                    locs[i].uri = src_file_uri;
                    locs[i].range = ranges[i];
                }
                if (TRet == []Location)
                    return Result(?TRet){ .ok = locs }
                else if (TRet == Locations)
                    return Result(?TRet){ .ok = .{ .locations = locs } }
                else
                    @compileError(@typeName(TRet));
            }
            return Result(?TRet){ .ok = null };
        }
    };
}

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    src_files_cache = std.StringHashMap(Str).init(&ctx.inst.mem_forever.?.allocator);
    std.debug.warn("\nonInitialized:\t{}\n", .{ctx.value});
    try ctx.inst.api.notify(.window_showMessage, ShowMessageParams{
        .@"type" = .Warning,
        .message = try std.fmt.allocPrint(ctx.mem, "So it's you... {}", .{ctx.inst.initialized.?.clientInfo.?.name}),
    });

    try ctx.inst.api.request(.client_registerCapability, {}, RegistrationParams{
        .registrations = &[1]Registration{Registration{
            .method = "workspace/didChangeWatchedFiles",
            .id = try zag.util.uniqueishId(ctx.mem, "dummylangserver_filewatch"),
            .registerOptions = try jsonic.AnyValue.fromStd(ctx.mem, &(try jsonrpc_options.json.marshal(ctx.mem, DidChangeWatchedFilesRegistrationOptions{
                .watchers = &[1]FileSystemWatcher{
                    FileSystemWatcher{
                        .globPattern = "**/*.dummy",
                    },
                },
            }))),
        }},
    }, struct {
        pub fn then(state: void, resp: Server.Ctx(Result(void))) error{}!void {
            std.debug.warn("Result of attempt to register for `workspace/didChangeWatchedFiles` notifications: {}\n", .{resp.value});
        }
    });
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    src_files_cache.deinit();
    return Result(void){ .ok = {} };
}
