const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
const jsonic = @import("../../jsonic/jsonic.zig");
usingnamespace jsonic.Rpc;
usingnamespace @import("./lsp_api_types.zig");

pub const api_client_side = api_server_side.inverse(null);

pub const api_server_side = Spec{
    .newReqId = @import("./lsp_common.zig").nextReqId,

    // incoming events / announcements from the LSP client counterparty
    .NotifyIn = union(enum) {
        @"$/cancelRequest": CancelParams,
        @"$/traceLogNotification": jsonic.AnyValue,
        @"$/setLogNotification": jsonic.AnyValue,
        @"initialized": InitializedParams,
        @"exit": void,
        @"workspace/didChangeWorkspaceFolders": DidChangeWorkspaceFoldersParams,
        @"workspace/didChangeConfiguration": DidChangeConfigurationParams,
        @"workspace/didChangeWatchedFiles": DidChangeWatchedFilesParams,
        @"textDocument/didOpen": DidOpenTextDocumentParams,
        @"textDocument/didChange": DidChangeTextDocumentParams,
        @"textDocument/willSave": WillSaveTextDocumentParams,
        @"textDocument/didSave": DidSaveTextDocumentParams,
        @"textDocument/didClose": DidCloseTextDocumentParams,
        @"window/workDoneProgress/cancel": WorkDoneProgressCancelParams,
    },

    // outgoing events / announcements / UX intentions to the LSP client counterparty
    .NotifyOut = union(enum) {
        @"$/progress": ProgressParams,
        @"window/showMessage": ShowMessageParams,
        @"window/logMessage": LogMessageParams,
        @"telemetry/event": jsonic.AnyValue,
        @"textDocument/publishDiagnostics": PublishDiagnosticsParams,
    },

    // outgoing requests to the LSP client that will bring a response
    .RequestOut = union(enum) {
        @"window/showMessageRequest": fn (ShowMessageRequestParams) void,
        @"window/workDoneProgress/create": fn (WorkDoneProgressCreateParams) void,
        @"client/registerCapability": fn (RegistrationParams) void,
        @"client/unregisterCapability": fn (UnregistrationParams) void,
        @"workspace/workspaceFolders": fn (void) ?[]WorkspaceFolder,
        @"workspace/configuration": fn (ConfigurationParams) []jsonic.AnyValue,
        @"workspace/applyEdit": fn (ApplyWorkspaceEditParams) ApplyWorkspaceEditResponse,
    },

    // incoming requests from the LSP client that necessitate producing a result in return
    .RequestIn = union(enum) {
        @"initialize": fn (InitializeParams) InitializeResult,
        @"shutdown": fn (void) void,
        @"workspace/symbol": fn (WorkspaceSymbolParams) ?[]SymbolInformation,
        @"workspace/executeCommand": fn (ExecuteCommandParams) ?jsonic.AnyValue,
        @"textDocument/willSaveWaitUntil": fn (WillSaveTextDocumentParams) ?[]TextEdit,
        @"textDocument/completion": fn (CompletionParams) ?CompletionList,
        @"completionItem/resolve": fn (CompletionItem) CompletionItem,
        @"textDocument/hover": fn (HoverParams) ?Hover,
        @"textDocument/signatureHelp": fn (SignatureHelpParams) ?SignatureHelp,
        @"textDocument/declaration": fn (DeclarationParams) ?Locations,
        @"textDocument/definition": fn (DefinitionParams) ?Locations,
        @"textDocument/typeDefinition": fn (TypeDefinitionParams) ?Locations,
        @"textDocument/implementation": fn (ImplementationParams) ?Locations,
        @"textDocument/references": fn (ReferenceParams) ?[]Location,
        @"textDocument/documentHighlight": fn (DocumentHighlightParams) ?[]DocumentHighlight,
        @"textDocument/documentSymbol": fn (DocumentSymbolParams) ?DocumentSymbols,
        @"textDocument/codeAction": fn (CodeActionParams) ?[]CommandOrAction,
        @"textDocument/codeLens": fn (CodeLensParams) ?[]CodeLens,
        @"codeLens/resolve": fn (CodeLens) CodeLens,
        @"textDocument/documentLink": fn (DocumentLinkParams) ?[]DocumentLink,
        @"documentLink/resolve": fn (DocumentLink) DocumentLink,
        @"textDocument/documentColor": fn (DocumentColorParams) []ColorInformation,
        @"textDocument/colorPresentation": fn (ColorPresentationParams) []ColorPresentation,
        @"textDocument/formatting": fn (DocumentFormattingParams) ?[]TextEdit,
        @"textDocument/rangeFormatting": fn (DocumentRangeFormattingParams) ?[]TextEdit,
        @"textDocument/onTypeFormatting": fn (DocumentOnTypeFormattingParams) ?[]TextEdit,
        @"textDocument/rename": fn (RenameParams) ?WorkspaceEdit,
        @"textDocument/prepareRename": fn (PrepareRenameParams) ?RenamePrep,
        @"textDocument/foldingRange": fn (FoldingRangeParams) ?[]FoldingRange,
        @"textDocument/selectionRange": fn (SelectionRangeParams) ?[]SelectionRange,
    },
};

pub const RenamePrep = union(enum) {
    range_only: Range,
    augmented: struct {
        range: Range,
        placeholder: Str,
    },
};

pub const DocumentSymbols = union(enum) {
    flat: []SymbolInformation,
    hierarchy: []DocumentSymbol,
};

pub const CommandOrAction = union(enum) {
    command_only: Command,
    code_action: CodeAction,
};

pub const Locations = union(enum) {
    locations: []Location,
    links: []LocationLink,
};
