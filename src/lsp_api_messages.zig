const std = @import("std");

usingnamespace @import("jsonic").JsonRpc;

usingnamespace @import("./lsp_api_types.zig");

pub const api_spec = Spec{
    .newReqId = nextReqId,

    // incoming events / announcements from the LSP client counterparty
    .NotifyIn = union(enum) {
        __cancelRequest: fn (Arg(CancelParams)) void,
        initialized: fn (Arg(InitializedParams)) void,
        exit: fn (Arg(void)) void,
        workspace_didChangeWorkspaceFolders: fn (Arg(DidChangeWorkspaceFoldersParams)) void,
        workspace_didChangeConfiguration: fn (Arg(DidChangeConfigurationParams)) void,
        workspace_didChangeWatchedFiles: fn (Arg(DidChangeWatchedFilesParams)) void,
        textDocument_didOpen: fn (Arg(DidOpenTextDocumentParams)) void,
        textDocument_didChange: fn (Arg(DidChangeTextDocumentParams)) void,
        textDocument_willSave: fn (Arg(WillSaveTextDocumentParams)) void,
        textDocument_didSave: fn (Arg(DidSaveTextDocumentParams)) void,
        textDocument_didClose: fn (Arg(DidCloseTextDocumentParams)) void,
    },

    // outgoing events / announcements / UX intentions to the LSP client counterparty
    .NotifyOut = union(enum) {
        __progress: ProgressParams,
        window_showMessage: ShowMessageParams,
        window_logMessage: LogMessageParams,
        telemetry_event: std.json.Value,
        textDocument_publishDiagnostics: PublishDiagnosticsParams,
    },

    // outgoing requests to the LSP client that will bring a response
    .RequestOut = union(enum) {
        window_showMessageRequest: fn (Arg(ShowMessageRequestParams)) Ret(void),
        window_workDoneProgress_create: fn (Arg(WorkDoneProgressCreateParams)) Ret(void),
        client_registerCapability: fn (Arg(RegistrationParams)) Ret(void),
        client_unregisterCapability: fn (Arg(UnregistrationParams)) Ret(void),
        workspace_workspaceFolders: fn (Arg(void)) Ret(?[]WorkspaceFolder),
        workspace_configuration: fn (Arg(ConfigurationParams)) Ret([]std.json.Value),
        workspace_applyEdit: fn (Arg(ApplyWorkspaceEditParams)) Ret(ApplyWorkspaceEditResponse),
    },

    // incoming requests from the LSP client that necessitate producing a result in return
    .RequestIn = union(enum) {
        initialize: fn (Arg(InitializeParams)) Ret(InitializeResult),
        shutdown: fn (Arg(void)) Ret(void),
        workspace_symbol: fn (Arg(WorkspaceSymbolParams)) Ret(?[]SymbolInformation),
        workspace_executeCommand: fn (Arg(ExecuteCommandParams)) Ret(?std.json.Value),
        textDocument_willSaveWaitUntil: fn (Arg(WillSaveTextDocumentParams)) Ret(?[]TextEdit),
        textDocument_completion: fn (Arg(CompletionParams)) Ret(?CompletionList),
        completionItem_resolve: fn (Arg(CompletionItem)) Ret(CompletionItem),
        textDocument_hover: fn (Arg(HoverParams)) Ret(?Hover),
        textDocument_signatureHelp: fn (Arg(SignatureHelpParams)) Ret(?SignatureHelp),
        textDocument_declaration: fn (Arg(DeclarationParams)) Ret(?union(enum) {
            locations: []Location,
            links: []LocationLink,
        }),
        textDocument_definition: fn (Arg(DefinitionParams)) Ret(?union(enum) {
            locations: []Location,
            links: []LocationLink,
        }),
        textDocument_typeDefinition: fn (Arg(TypeDefinitionParams)) Ret(?union(enum) {
            locations: []Location,
            links: []LocationLink,
        }),
        textDocument_implementation: fn (Arg(ImplementationParams)) Ret(?union(enum) {
            locations: []Location,
            links: []LocationLink,
        }),
        textDocument_references: fn (Arg(ReferenceParams)) Ret(?[]Location),
        textDocument_documentHighlight: fn (Arg(DocumentHighlightParams)) Ret(?[]DocumentHighlight),
        textDocument_documentSymbol: fn (Arg(DocumentSymbolParams)) Ret(?union(enum) {
            flat: []SymbolInformation,
            hierarchy: []DocumentSymbol,
        }),
        textDocument_codeAction: fn (Arg(CodeActionParams)) Ret(?[]union(enum) {
            code_action: CodeAction,
            command: Command,
        }),
        textDocument_codeLens: fn (Arg(CodeLensParams)) Ret(?[]CodeLens),
        codeLens_resolve: fn (Arg(CodeLens)) Ret(CodeLens),
        textDocument_documentLink: fn (Arg(DocumentLinkParams)) Ret(?[]DocumentLink),
        documentLink_resolve: fn (Arg(DocumentLink)) Ret(DocumentLink),
        textDocument_documentColor: fn (Arg(DocumentColorParams)) Ret([]ColorInformation),
        textDocument_colorPresentation: fn (Arg(ColorPresentationParams)) Ret([]ColorPresentation),
        textDocument_formatting: fn (Arg(DocumentFormattingParams)) Ret(?[]TextEdit),
        textDocument_rangeFormatting: fn (Arg(DocumentRangeFormattingParams)) Ret(?[]TextEdit),
        textDocument_onTypeFormatting: fn (Arg(DocumentOnTypeFormattingParams)) Ret(?[]TextEdit),
        textDocument_rename: fn (Arg(RenameParams)) Ret(?[]WorkspaceEdit),
        textDocument_prepareRename: fn (Arg(TextDocumentPositionParams)) Ret(?Range),
        textDocument_foldingRange: fn (Arg(FoldingRangeParams)) Ret(?[]FoldingRange),
        textDocument_selectionRange: fn (Arg(SelectionRangeParams)) Ret(?[]SelectionRange),
    },
};

fn nextReqId(owner: *std.mem.Allocator) !std.json.Value {
    const global_counter = struct {
        var req_id: isize = 0;
    };
    global_counter.req_id += 1;
    var buf = try std.Buffer.init(owner, "demo_req_id_"); // no defer-deinit! would destroy our return value
    try std.fmt.formatIntValue(global_counter.req_id, "", std.fmt.FormatOptions{}, &buf, @TypeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append);
    return std.json.Value{ .String = buf.toOwnedSlice() };
}
