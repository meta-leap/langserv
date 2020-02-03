const std = @import("std");

usingnamespace @import("jsonic").JsonRpc;

usingnamespace @import("lsp_types.zig");

pub const NotifyIn = union(enum) {
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
};

pub const NotifyOut = union(enum) {
    __progress: ProgressParams,
    window_showMessage: ShowMessageParams,
    window_logMessage: LogMessageParams,
    telemetry_event: JsonAny,
    textDocument_publishDiagnostics: PublishDiagnosticsParams,
};

pub const RequestIn = union(enum) {
    initialize: fn (Arg(InitializeParams)) Out(InitializeResult),
    shutdown: fn (Arg(void)) Out(void),
    workspace_symbol: fn (Arg(WorkspaceSymbolParams)) Out(?[]SymbolInformation),
    workspace_executeCommand: fn (Arg(ExecuteCommandParams)) Out(?JsonAny),
    textDocument_willSaveWaitUntil: fn (Arg(WillSaveTextDocumentParams)) Out(?[]TextEdit),
    textDocument_completion: fn (Arg(CompletionParams)) Out(?CompletionList),
    completionItem_resolve: fn (Arg(CompletionItem)) Out(CompletionItem),
    textDocument_hover: fn (Arg(HoverParams)) Out(?Hover),
    textDocument_signatureHelp: fn (Arg(SignatureHelpParams)) Out(?SignatureHelp),
    textDocument_declaration: fn (Arg(DeclarationParams)) Out(?union(enum) {
        locations: []Location,
        links: []LocationLink,
    }),
    textDocument_definition: fn (Arg(DefinitionParams)) Out(?union(enum) {
        locations: []Location,
        links: []LocationLink,
    }),
    textDocument_typeDefinition: fn (Arg(TypeDefinitionParams)) Out(?union(enum) {
        locations: []Location,
        links: []LocationLink,
    }),
    textDocument_implementation: fn (Arg(ImplementationParams)) Out(?union(enum) {
        locations: []Location,
        links: []LocationLink,
    }),
    textDocument_references: fn (Arg(ReferenceParams)) Out(?[]Location),
    textDocument_documentHighlight: fn (Arg(DocumentHighlightParams)) Out(?[]DocumentHighlight),
    textDocument_documentSymbol: fn (Arg(DocumentSymbolParams)) Out(?union(enum) {
        flat: []SymbolInformation,
        hierarchy: []DocumentSymbol,
    }),
    textDocument_codeAction: fn (Arg(CodeActionParams)) Out(?[]union(enum) {
        code_action: CodeAction,
        command: Command,
    }),
    textDocument_codeLens: fn (Arg(CodeLensParams)) Out(?[]CodeLens),
    codeLens_resolve: fn (Arg(CodeLens)) Out(CodeLens),
    textDocument_documentLink: fn (Arg(DocumentLinkParams)) Out(?[]DocumentLink),
    documentLink_resolve: fn (Arg(DocumentLink)) Out(DocumentLink),
    textDocument_documentColor: fn (Arg(DocumentColorParams)) Out([]ColorInformation),
    textDocument_colorPresentation: fn (Arg(ColorPresentationParams)) Out([]ColorPresentation),
    textDocument_formatting: fn (Arg(DocumentFormattingParams)) Out(?[]TextEdit),
    textDocument_rangeFormatting: fn (Arg(DocumentRangeFormattingParams)) Out(?[]TextEdit),
    textDocument_onTypeFormatting: fn (Arg(DocumentOnTypeFormattingParams)) Out(?[]TextEdit),
    textDocument_rename: fn (Arg(RenameParams)) Out(?[]WorkspaceEdit),
    textDocument_prepareRename: fn (Arg(TextDocumentPositionParams)) Out(?Range),
    textDocument_foldingRange: fn (Arg(FoldingRangeParams)) Out(?[]FoldingRange),
    textDocument_selectionRange: fn (Arg(SelectionRangeParams)) Out(?[]SelectionRange),
};

pub const RequestOut = union(enum) {
    window_showMessageRequest: Req(ShowMessageRequestParams, void),
    window_workDoneProgress_create: Req(WorkDoneProgressCreateParams, void),
    client_registerCapability: Req(RegistrationParams, void),
    client_unregisterCapability: Req(UnregistrationParams, void),
    workspace_workspaceFolders: Req(void, ?[]WorkspaceFolder),
    workspace_configuration: Req(ConfigurationParams, []JsonAny),
    workspace_applyEdit: Req(ApplyWorkspaceEditParams, ApplyWorkspaceEditResponse),
};
