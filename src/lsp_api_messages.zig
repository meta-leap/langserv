const std = @import("std");
const jsonic = @import("../../jsonic/api.zig");

usingnamespace jsonic.Rpc;

usingnamespace @import("./lsp_api_types.zig");

pub const api_client_side = api_server_side.inverse(null);

pub const api_server_side = Spec{
    .newReqId = @import("./lsp_common.zig").nextReqId,

    // incoming events / announcements from the LSP client counterparty
    .NotifyIn = union(enum) {
        __cancelRequest: CancelParams,
        __traceLogNotification: jsonic.AnyValue,
        __setLogNotification: jsonic.AnyValue,
        initialized: InitializedParams,
        exit: void,
        workspace_didChangeWorkspaceFolders: DidChangeWorkspaceFoldersParams,
        workspace_didChangeConfiguration: DidChangeConfigurationParams,
        workspace_didChangeWatchedFiles: DidChangeWatchedFilesParams,
        textDocument_didOpen: DidOpenTextDocumentParams,
        textDocument_didChange: DidChangeTextDocumentParams,
        textDocument_willSave: WillSaveTextDocumentParams,
        textDocument_didSave: DidSaveTextDocumentParams,
        textDocument_didClose: DidCloseTextDocumentParams,
    },

    // outgoing events / announcements / UX intentions to the LSP client counterparty
    .NotifyOut = union(enum) {
        __progress: ProgressParams,
        window_showMessage: ShowMessageParams,
        window_logMessage: LogMessageParams,
        telemetry_event: jsonic.AnyValue,
        textDocument_publishDiagnostics: PublishDiagnosticsParams,
    },

    // outgoing requests to the LSP client that will bring a response
    .RequestOut = union(enum) {
        window_showMessageRequest: fn (ShowMessageRequestParams) void,
        window_workDoneProgress_create: fn (WorkDoneProgressCreateParams) void,
        client_registerCapability: fn (RegistrationParams) void,
        client_unregisterCapability: fn (UnregistrationParams) void,
        workspace_workspaceFolders: fn (void) ?[]WorkspaceFolder,
        workspace_configuration: fn (ConfigurationParams) []jsonic.AnyValue,
        workspace_applyEdit: fn (ApplyWorkspaceEditParams) ApplyWorkspaceEditResponse,
    },

    // incoming requests from the LSP client that necessitate producing a result in return
    .RequestIn = union(enum) {
        initialize: fn (InitializeParams) InitializeResult,
        shutdown: fn (void) void,
        workspace_symbol: fn (WorkspaceSymbolParams) ?[]SymbolInformation,
        workspace_executeCommand: fn (ExecuteCommandParams) ?jsonic.AnyValue,
        textDocument_willSaveWaitUntil: fn (WillSaveTextDocumentParams) ?[]TextEdit,
        textDocument_completion: fn (CompletionParams) ?CompletionList,
        completionItem_resolve: fn (CompletionItem) CompletionItem,
        textDocument_hover: fn (HoverParams) ?Hover,
        textDocument_signatureHelp: fn (SignatureHelpParams) ?SignatureHelp,
        textDocument_declaration: fn (DeclarationParams) ?Locations,
        textDocument_definition: fn (DefinitionParams) ?Locations,
        textDocument_typeDefinition: fn (TypeDefinitionParams) ?Locations,
        textDocument_implementation: fn (ImplementationParams) ?Locations,
        textDocument_references: fn (ReferenceParams) ?[]Location,
        textDocument_documentHighlight: fn (DocumentHighlightParams) ?[]DocumentHighlight,
        textDocument_documentSymbol: fn (DocumentSymbolParams) ?DocumentSymbols,
        textDocument_codeAction: fn (CodeActionParams) ?CodeActions,
        textDocument_codeLens: fn (CodeLensParams) ?[]CodeLens,
        codeLens_resolve: fn (CodeLens) CodeLens,
        textDocument_documentLink: fn (DocumentLinkParams) ?[]DocumentLink,
        documentLink_resolve: fn (DocumentLink) DocumentLink,
        textDocument_documentColor: fn (DocumentColorParams) []ColorInformation,
        textDocument_colorPresentation: fn (ColorPresentationParams) []ColorPresentation,
        textDocument_formatting: fn (DocumentFormattingParams) ?[]TextEdit,
        textDocument_rangeFormatting: fn (DocumentRangeFormattingParams) ?[]TextEdit,
        textDocument_onTypeFormatting: fn (DocumentOnTypeFormattingParams) ?[]TextEdit,
        textDocument_rename: fn (RenameParams) ?WorkspaceEdit,
        textDocument_prepareRename: fn (TextDocumentPositionParams) ?RenamePrep,
        textDocument_foldingRange: fn (FoldingRangeParams) ?[]FoldingRange,
        textDocument_selectionRange: fn (SelectionRangeParams) ?[]SelectionRange,
    },
};

pub const RenamePrep = union(enum) {
    range_only: Range,
    augmented: struct {
        range: Range,
        placeholder: String,
    },
};

pub const DocumentSymbols = union(enum) {
    flat: []SymbolInformation,
    hierarchy: []DocumentSymbol,
};

pub const CodeActions = []union(enum) {
    code_action: CodeAction,
    command: Command,
};

pub const Locations = union(enum) {
    locations: []Location,
    links: []LocationLink,
};
