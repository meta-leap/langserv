const std = @import("std");
const jsonic = @import("../../jsonic/api.zig");

// TODO: catch up on spec changes since last check of: 06 Feb 2020
// https://microsoft.github.io/language-server-protocol/specifications/specification-current/
// https://github.com/Microsoft/language-server-protocol/blob/gh-pages/_specifications/specification-3-15.md

pub const String = []const u8;

pub const ErrorCodes = enum(isize) {
    RequestCancelled = -32800,
    ContentModified = -32801,
};

pub const CancelParams = struct {
    id: jsonic.AnyValue,
};

pub const DocumentUri = String;

pub const Position = struct {
    line: isize,
    character: isize,

    pub fn fromByteIndexIn(string: []const u8, index: usize) !?Position {
        if (index < string.len) {
            var cur = Position{ .line = 0, .character = 0 };
            var i: usize = 0;
            while (i < string.len) {
                if (i >= index)
                    return cur;
                if (string[i] == '\n') {
                    cur.line += 1;
                    cur.character = 0;
                    i += 1;
                } else {
                    cur.character += 1;
                    i += try std.unicode.utf8ByteSequenceLength(string[i]);
                }
            }
        }
        return null;
    }

    pub fn toByteIndexIn(me: *const Position, string: []const u8) !?usize {
        var cur = Position{ .line = 0, .character = 0 };
        var i: usize = 0;
        while (i < string.len) {
            if (cur.line == me.line and cur.character == me.character)
                return i;
            if (string[i] == '\n') {
                cur.line += 1;
                cur.character = 0;
                i += 1;
            } else {
                cur.character += 1;
                i += try std.unicode.utf8ByteSequenceLength(string[i]);
            }
        }
        return null;
    }
};

pub const Range = struct {
    start: Position,
    end: Position,

    pub fn initFrom(string: []const u8) !?Range {
        if (try Position.fromByteIndexIn(string, string.len - 1)) |last_pos|
            return Range{ .start = .{ .line = 0, .character = 0 }, .end = last_pos };
        return null;
    }

    pub fn slice(me: *Range, string: []const u8) !?[]const u8 {
        var cur = Position{ .line = 0, .character = 0 };
        var idx_start: ?usize = null;
        var idx_end: ?usize = null;
        var i: usize = 0;
        while (i < string.len and (idx_start == null or idx_end == null)) {
            if (idx_end == null and cur.line == me.end.line and cur.character == me.end.character)
                idx_end = i;
            if (idx_start == null and cur.line == me.start.line and cur.character == me.start.character)
                idx_start = i;
            if (string[i] == '\n') {
                cur.line += 1;
                cur.character = 0;
                i += 1;
            } else {
                cur.character += 1;
                i += try std.unicode.utf8ByteSequenceLength(string[i]);
            }
        }
        if (idx_start) |i_start| {
            if (idx_end) |i_end|
                return string[i_start..i_end];
        }
        return null;
    }
};

pub const Location = struct {
    uri: DocumentUri,
    range: Range,
};

pub const LocationLink = struct {
    originSelectionRange: ?Range = null,
    targetUri: DocumentUri,
    targetRange: Range,
    targetSelectionRange: Range,
};

pub const Diagnostic = struct {
    range: Range,
    severity: ?enum {
        __ = 0,
        Error = 1,
        Warning = 2,
        Information = 3,
        Hint = 4,
    } = null,
    code: ?jsonic.AnyValue = null,
    source: ?String = null,
    message: String,
    tags: ?[]DiagnosticTag = null,
    relatedInformation: ?[]DiagnosticRelatedInformation = null,
};

pub const DiagnosticTag = enum {
    __ = 0,
    Unnecessary = 1,
    Deprecated = 2,
};

pub const DiagnosticRelatedInformation = struct {
    location: Location,
    message: String,
};

pub const Command = struct {
    title: String,
    command: String,
    arguments: ?[]jsonic.AnyValue = null,
};

pub const TextEdit = struct {
    range: Range,
    newText: String,
};

pub const TextDocumentEdit = struct {
    textDocument: VersionedTextDocumentIdentifier,
    edits: []TextEdit,
};

pub const VersionedTextDocumentIdentifier = struct {
    TextDocumentIdentifier: TextDocumentIdentifier,
    version: ?isize = null,
};

pub const TextDocumentPositionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

pub const TextDocumentIdentifier = struct {
    uri: DocumentUri,
};

pub const WorkspaceEdit = struct {
    changes: ?std.StringHashMap([]TextEdit) = null,
    documentChanges: ?[]union(enum) {
        edit: TextDocumentEdit,
        file_create: struct {
            kind: String = Kind.Create,
            uri: DocumentUri,
            options: ?struct {
                overwrite: ?bool = null,
                ignoreIfExists: ?bool = null,
            } = null,
        },
        file_rename: struct {
            kind: String = Kind.Rename,
            oldUri: DocumentUri,
            newUri: DocumentUri,
            options: ?struct {
                overwrite: ?bool = null,
                ignoreIfExists: ?bool = null,
            } = null,
        },
        file_delete: struct {
            kind: String = Kind.Delete,
            uri: DocumentUri,
            options: ?struct {
                recursive: ?bool = null,
                ignoreIfNotExists: ?bool = null,
            } = null,
        },

        pub const Kind = struct {
            pub const Create: String = "create";
            pub const Rename: String = "rename";
            pub const Delete: String = "delete";
        };
    } = null,
};

pub const TextDocumentItem = struct {
    uri: DocumentUri,
    languageId: String,
    version: isize,
    text: String,
};

pub const DocumentFilter = struct {
    language: ?String = null,
    scheme: ?String = null,
    pattern: ?String = null,
};

pub const DocumentSelector = []DocumentFilter;

pub const MarkupContent = struct {
    kind: String = Kind.markdown,
    value: String,

    pub const Kind = struct {
        pub const plaintext = "plaintext";
        pub const markdown = "markdown";
    };
};

pub const InitializeParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    processId: ?isize = null,
    clientInfo: ?struct {
        name: String,
        version: ?String = null,
    } = null,
    rootUri: ?DocumentUri = null,
    initializationOptions: ?jsonic.AnyValue = null,
    capabilities: ClientCapabilities,
    trace: ?String = null,
    workspaceFolders: ?[]WorkspaceFolder = null,

    pub const Trace = struct {
        pub const off = "off";
        pub const messages = "messages";
        pub const verbose = "verbose";
    };
};

pub const CodeActionKind = struct {
    pub const Empty = "";
    pub const QuickFix = "quickfix";
    pub const Refactor = "refactor";
    pub const RefactorExtract = "refactor.extract";
    pub const RefactorInline = "refactor.inline";
    pub const RefactorRewrite = "refactor.rewrite";
    pub const Source = "source";
    pub const SourceOrganizeImports = "source.organizeImports";
};

pub const CompletionItemTag = enum {
    __ = 0,
    Deprecated = 1,
};

pub const CompletionItemKind = enum {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
};

pub const SymbolKind = enum {
    File = 1,
    Module = 2,
    Namespace = 3,
    Package = 4,
    Class = 5,
    Method = 6,
    Property = 7,
    Field = 8,
    Constructor = 9,
    Enum = 10,
    Interface = 11,
    Function = 12,
    Variable = 13,
    Constant = 14,
    String = 15,
    Number = 16,
    Boolean = 17,
    Array = 18,
    Object = 19,
    Key = 20,
    Null = 21,
    EnumMember = 22,
    Struct = 23,
    Event = 24,
    Operator = 25,
    TypeParameter = 26,
};

pub const ClientCapabilities = struct {
    workspace: ?struct {
        applyEdit: ?bool = null,
        workspaceEdit: ?WorkspaceEditClientCapabilities = null,
        didChangeConfiguration: ?DidChangeConfigurationClientCapabilities = null,
        didChangeWatchedFiles: ?DidChangeWatchedFilesClientCapabilities = null,
        symbol: ?WorkspaceSymbolClientCapabilities = null,
        executeCommand: ?ExecuteCommandClientCapabilities = null,
        workspaceFolders: ?bool = null,
        configuration: ?bool = null,
    } = null,
    textDocument: ?TextDocumentClientCapabilities = null,
    // experimental: ?jsonic.AnyValue = null,

    pub const ExecuteCommandClientCapabilities = struct {
        dynamicRegistration: ?bool = null,
    };

    pub const WorkspaceSymbolClientCapabilities = struct {
        dynamicRegistration: ?bool = null,
        symbolKind: ?struct {
            valueSet: ?[]SymbolKind = null,
        } = null,
    };

    pub const DidChangeWatchedFilesClientCapabilities = struct {
        dynamicRegistration: ?bool = null,
    };

    pub const DidChangeConfigurationClientCapabilities = struct {
        dynamicRegistration: ?bool = null,
    };

    pub const WorkspaceEditClientCapabilities = struct {
        documentChanges: ?bool = null,
        resourceOperations: ?[]String = null,
        failureHandling: ?String = null,

        pub const ResourceOperationKind = struct {
            pub const Create = "create";
            pub const Rename = "rename";
            pub const Delete = "delete";
        };

        pub const FailureHandlingKind = struct {
            pub const Abort = "abort";
            pub const Transactional = "transactional";
            pub const TextOnlyTransactional = "textOnlyTransactional";
            pub const Undo = "undo";
        };
    };

    pub const TextDocumentClientCapabilities = struct {
        selectionRange: ?SelectionRangeClientCapabilities = null,
        synchronization: ?TextDocumentSyncClientCapabilities = null,
        completion: ?CompletionClientCapabilities = null,
        hover: ?HoverClientCapabilities = null,
        signatureHelp: ?SignatureHelpClientCapabilities = null,
        references: ?ReferenceClientCapabilities = null,
        documentHighlight: ?DocumentHighlightClientCapabilities = null,
        documentSymbol: ?DocumentSymbolClientCapabilities = null,
        formatting: ?DocumentFormattingClientCapabilities = null,
        rangeFormatting: ?DocumentRangeFormattingClientCapabilities = null,
        onTypeFormatting: ?DocumentOnTypeFormattingClientCapabilities = null,
        declaration: ?DeclarationClientCapabilities = null,
        definition: ?DefinitionClientCapabilities = null,
        typeDefinition: ?TypeDefinitionClientCapabilities = null,
        implementation: ?ImplementationClientCapabilities = null,
        codeAction: ?CodeActionClientCapabilities = null,
        codeLens: ?CodeLensClientCapabilities = null,
        documentLink: ?DocumentLinkClientCapabilities = null,
        colorProvider: ?DocumentColorClientCapabilities = null,
        rename: ?RenameClientCapabilities = null,
        publishDiagnostics: ?PublishDiagnosticsClientCapabilities = null,
        foldingRange: ?FoldingRangeClientCapabilities = null,

        pub const FoldingRangeClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            rangeLimit: ?isize = null,
            lineFoldingOnly: ?bool = null,
        };
        pub const CodeLensClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const DocumentLinkClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            tooltipSupport: ?bool = null,
        };
        pub const DocumentColorClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const TextDocumentSyncClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            willSave: ?bool = null,
            willSaveWaitUntil: ?bool = null,
            didSave: ?bool = null,
        };
        pub const CompletionClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            completionItem: ?struct {
                snippetSupport: ?bool = null,
                commitCharactersSupport: ?bool = null,
                documentationFormat: ?[]String = null,
                deprecatedSupport: ?bool = null,
                preselectSupport: ?bool = null,
                tagSupport: ?struct {
                    valueSet: ?[]CompletionItemTag = null,
                } = null,
            } = null,
            completionItemKind: ?struct {
                valueSet: ?[]CompletionItemKind,
            } = null,
            contextSupport: ?bool = null,
        };
        pub const SelectionRangeClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const HoverClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            contentFormat: ?[]String = null,
        };
        pub const SignatureHelpClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            signatureInformation: ?struct {
                documentationFormat: ?[]String = null,
                parameterInformation: ?struct {
                    labelOffsetSupport: ?bool = null,
                } = null,
            } = null,
            contextSupport: ?bool = null,
        };
        pub const DeclarationClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            linkSupport: ?bool = null,
        };
        pub const DefinitionClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            linkSupport: ?bool = null,
        };
        pub const ReferenceClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const DocumentHighlightClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const DocumentSymbolClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            symbolKind: ?struct {
                valueSet: ?[]SymbolKind = null,
            } = null,
            hierarchicalDocumentSymbolSupport: ?bool = null,
        };
        pub const DocumentFormattingClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const DocumentRangeFormattingClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const DocumentOnTypeFormattingClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
        };
        pub const RenameClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            prepareSupport: ?bool = null,
        };
        pub const PublishDiagnosticsClientCapabilities = struct {
            relatedInformation: ?bool = null,
            tagSupport: ?struct {
                valueSet: []DiagnosticTag,
            } = null,
            versionSupport: ?bool = null,
        };
        pub const TypeDefinitionClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            linkSupport: ?bool = null,
        };
        pub const ImplementationClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            linkSupport: ?bool = null,
        };
        pub const CodeActionClientCapabilities = struct {
            dynamicRegistration: ?bool = null,
            codeActionLiteralSupport: ?struct {
                codeActionKind: struct {
                    valueSet: []String,
                },
            } = null,
            isPreferredSupport: ?bool = null,
        };
    };
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    serverInfo: ?struct {
        name: String,
        version: ?String = null,
    } = null,
};

pub const TextDocumentSyncKind = enum {
    None = 0,
    Full = 1,
    Incremental = 2,
};

pub const WorkDoneProgressOptions = struct {
    workDoneProgress: ?bool = null,
};

pub const DocumentOnTypeFormattingOptions = struct {
    firstTriggerCharacter: String,
    moreTriggerCharacter: ?[]String = null,
};

pub const DocumentLinkOptions = struct {
    WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
    TextDocumentRegistrationOptions: TextDocumentRegistrationOptions,
    resolveProvider: ?bool = null,
};

pub const SaveOptions = struct {
    includeText: ?bool = null,
};

pub const TextDocumentSyncOptions = struct {
    openClose: ?bool = null,
    change: ?TextDocumentSyncKind = null,
    willSave: ?bool = null,
    willSaveWaitUntil: ?bool = null,
    save: ?SaveOptions = null,
};

pub const StaticRegistrationOptions = struct {
    id: ?String = null,
};

pub const ServerCapabilities = struct {
    textDocumentSync: ?union(enum) {
        legacy: TextDocumentSyncKind,
        options: TextDocumentSyncOptions,
    } = null,
    completionProvider: ?CompletionOptions = null,
    hoverProvider: ?union(enum) {
        enabled: bool,
        options: HoverOptions,
    } = null,
    signatureHelpProvider: ?SignatureHelpOptions = null,
    definitionProvider: ?union(enum) {
        enabled: bool,
        options: DefinitionOptions,
    } = null,
    typeDefinitionProvider: ?union(enum) {
        enabled: bool,
        options: TypeDefinitionOptions,
    } = null,
    implementationProvider: ?union(enum) {
        enabled: bool,
        options: ImplementationOptions,
    } = null,
    referencesProvider: ?union(enum) {
        enabled: bool,
        options: ReferenceOptions,
    } = null,
    documentHighlightProvider: ?union(enum) {
        enabled: bool,
        options: DocumentHighlightOptions,
    } = null,
    documentSymbolProvider: ?union(enum) {
        enabled: bool,
        options: DocumentSymbolOptions,
    } = null,
    workspaceSymbolProvider: ?union(enum) {
        enabled: bool,
        options: WorkspaceSymbolOptions,
    } = null,
    codeActionProvider: ?union(enum) {
        enabled: bool,
        options: CodeActionOptions,
    } = null,
    codeLensProvider: ?CodeLensOptions = null,
    documentFormattingProvider: ?union(enum) {
        enabled: bool,
        options: DocumentFormattingOptions,
    } = null,
    documentRangeFormattingProvider: ?union(enum) {
        enabled: bool,
        options: DocumentRangeFormattingOptions,
    } = null,
    documentOnTypeFormattingProvider: ?DocumentOnTypeFormattingOptions = null,
    renameProvider: ?union(enum) {
        enabled: bool,
        options: RenameOptions,
    } = null,
    documentLinkProvider: ?DocumentLinkOptions = null,
    colorProvider: ?bool = null,
    foldingRangeProvider: ?union(enum) {
        enabled: bool,
        options: FoldingRangeOptions,
    } = null,
    declarationProvider: ?union(enum) {
        enabled: bool,
        options: DeclarationOptions,
    } = null,
    executeCommandProvider: ?ExecuteCommandOptions = null,
    workspace: ?WorkspaceOptions = null,
    selectionRangeProvider: ?union(enum) {
        enabled: bool,
        options: SelectionRangeOptions,
    } = null,
    // experimental: ?jsonic.AnyValue = null,

    pub const CodeLensOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        resolveProvider: ?bool = null,
    };

    pub const WorkspaceOptions = struct {
        workspaceFolders: ?WorkspaceFoldersServerCapabilities = null,
    };

    pub const WorkspaceFoldersServerCapabilities = struct {
        supported: ?bool = null,
        changeNotifications: ?union(enum) {
            enabled: bool,
            registrationId: String,
        } = null,
    };

    pub const ExecuteCommandOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        commands: []String,
    };

    pub const CodeActionOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        codeActionKinds: ?[]String = null,
    };

    pub const RenameOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        prepareProvider: ?bool = null,
    };

    pub const DefinitionOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const TypeDefinitionOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        StaticRegistrationOptions: ?StaticRegistrationOptions = null,
    };

    pub const ImplementationOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        StaticRegistrationOptions: ?StaticRegistrationOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const ReferenceOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const DocumentHighlightOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const DocumentSymbolOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const DocumentFormattingOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const DocumentRangeFormattingOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const FoldingRangeOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        StaticRegistrationOptions: ?StaticRegistrationOptions = null,
    };

    pub const SelectionRangeOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        StaticRegistrationOptions: ?StaticRegistrationOptions = null,
    };

    pub const CompletionOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        resolveProvider: ?bool = null,
        triggerCharacters: ?[]String = null,
        allCommitCharacters: ?[]String = null,
    };

    pub const HoverOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
    };

    pub const SignatureHelpOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        triggerCharacters: ?[]String = null,
        retriggerCharacters: ?[]String = null,
    };

    pub const WorkspaceSymbolOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
    };

    pub const DeclarationOptions = struct {
        WorkDoneProgressOptions: ?WorkDoneProgressOptions = null,
        TextDocumentRegistrationOptions: ?TextDocumentRegistrationOptions = null,
        StaticRegistrationOptions: ?StaticRegistrationOptions = null,
    };
};

pub const InitializedParams = struct {};

pub const ShowMessageParams = struct {
    type__: MessageType,
    message: String,
};

pub const MessageType = enum {
    __ = 0,
    Error = 1,
    Warning = 2,
    Info = 3,
    Log = 4,
};

pub const ShowMessageRequestParams = struct {
    type__: MessageType,
    message: String,
    actions: ?[]MessageActionItem = null,
};

pub const MessageActionItem = struct {
    title: String,
};

pub const LogMessageParams = struct {
    type__: MessageType,
    message: String,
};

pub const Registration = struct {
    id: String,
    method: String,
    registerOptions: ?jsonic.AnyValue = null,
};

pub const RegistrationParams = struct {
    registrations: []Registration,
};

pub const TextDocumentRegistrationOptions = struct {
    documentSelector: ?DocumentSelector = null,
};

pub const Unregistration = struct {
    id: String,
    method: String,
};

pub const UnregistrationParams = struct {
    unregisterations: []Unregistration,
};

pub const WorkspaceFolder = struct {
    uri: DocumentUri,
    name: String,
};

pub const DidChangeWorkspaceFoldersParams = struct {
    event: WorkspaceFoldersChangeEvent,
};

pub const WorkspaceFoldersChangeEvent = struct {
    added: []WorkspaceFolder,
    removed: []WorkspaceFolder,
};

pub const DidChangeConfigurationParams = struct {
    settings: jsonic.AnyValue,
};

pub const ConfigurationParams = struct {
    items: []ConfigurationItem,
};

pub const ConfigurationItem = struct {
    scopeUri: ?DocumentUri = null,
    section: ?String = null,
};

pub const DidChangeWatchedFilesParams = struct {
    changes: []FileEvent,
};

pub const FileEvent = struct {
    uri: DocumentUri,
    type__: enum {
        __ = 0,
        Created = 1,
        Changed = 2,
        Deleted = 3,
    },
};

pub const DidChangeWatchedFilesRegistrationOptions = struct {
    watchers: []FileSystemWatcher,
};

pub const FileSystemWatcher = struct {
    globPattern: String,
    kind: ?enum {
        Created = 1,
        Changed = 2,
        Deleted = 3,
    } = null,
};

pub const WorkspaceSymbolParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    query: String,
};

pub const ExecuteCommandParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    command: String,
    arguments: ?[]jsonic.AnyValue = null,
};

pub const ExecuteCommandRegistrationOptions = struct {
    commands: []String,
};

pub const ApplyWorkspaceEditParams = struct {
    label: ?String = null,
    edit: WorkspaceEdit,
};

pub const ApplyWorkspaceEditResponse = struct {
    applied: bool,
    failureReason: ?String = null,
};

pub const DidOpenTextDocumentParams = struct {
    textDocument: TextDocumentItem,
};

pub const DidChangeTextDocumentParams = struct {
    textDocument: VersionedTextDocumentIdentifier,
    contentChanges: []TextDocumentContentChangeEvent,
};

pub const TextDocumentContentChangeEvent = struct {
    range: ?Range = null,
    text: String,
};

pub const TextDocumentChangeRegistrationOptions = struct {
    TextDocumentRegistrationOptions: TextDocumentRegistrationOptions,
    syncKind: TextDocumentSyncKind,
};

pub const WillSaveTextDocumentParams = struct {
    textDocument: TextDocumentIdentifier,
    reason: ?enum {
        Manual = 1,
        AfterDelay = 2,
        FocusOut = 3,
    } = null,
};

pub const DidSaveTextDocumentParams = struct {
    textDocument: TextDocumentIdentifier,
    text: ?String = null,
};

pub const TextDocumentSaveRegistrationOptions = struct {
    TextDocumentRegistrationOptions: TextDocumentRegistrationOptions,
    includeText: ?bool = null,
};

pub const DidCloseTextDocumentParams = struct {
    textDocument: TextDocumentIdentifier,
};

pub const PublishDiagnosticsParams = struct {
    uri: DocumentUri,
    version: ?isize = null,
    diagnostics: []Diagnostic,
};

pub const CompletionParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    context: ?CompletionContext = null,
};

pub const CompletionTriggerKind = enum {
    Invoked = 1,
    TriggerCharacter = 2,
    TriggerForIncompleteCompletions = 3,
};

pub const CompletionContext = struct {
    triggerKind: ?CompletionTriggerKind = null,
    triggerCharacter: ?String = null,
};

pub const CompletionList = struct {
    isIncomplete: bool = false,
    items: []CompletionItem,
};

pub const InsertTextFormat = enum {
    __ = 0,
    PlainText = 1,
    Snippet = 2,
};

pub const CompletionItem = struct {
    label: String,
    kind: ?CompletionItemKind = null,
    tags: ?[]CompletionItemTag = null,
    detail: ?String = null,
    documentation: ?MarkupContent = null,
    preselect: ?bool = null,
    sortText: ?String = null,
    filterText: ?String = null,
    insertText: ?String = null,
    insertTextFormat: ?InsertTextFormat = null,
    textEdit: ?TextEdit = null,
    additionalTextEdits: ?[]TextEdit = null,
    commitCharacters: ?[]String = null,
    command: ?String = null,
    // data: ?jsonic.AnyValue = null,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

pub const SignatureHelp = struct {
    signatures: []SignatureInformation,
    activeSignature: ?isize = null,
    activeParameter: ?isize = null,
};

pub const SignatureInformation = struct {
    label: String,
    documentation: ?MarkupContent = null,
    parameters: ?[]ParameterInformation = null,
};

pub const ParameterInformation = struct {
    label: String,
    documentation: ?MarkupContent = null,
};

pub const ReferenceParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    context: ReferenceContext,
};

pub const ReferenceContext = struct {
    includeDeclaration: bool,
};

pub const DocumentHighlight = struct {
    range: Range,
    kind: ?enum {
        Text = 1,
        Read = 2,
        Write = 3,
    } = null,
};

pub const DocumentSymbolParams = struct {
    textDocument: TextDocumentIdentifier,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const DocumentSymbol = struct {
    name: String,
    detail: ?String = null,
    kind: SymbolKind,
    deprecated: ?bool = null,
    range: Range,
    selectionRange: Range,
    children: ?[]DocumentSymbol = null,
};

pub const SymbolInformation = struct {
    name: String,
    kind: SymbolKind,
    deprecated: ?bool = null,
    location: Location,
    containerName: ?String = null,
};

pub const CodeActionParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    textDocument: TextDocumentIdentifier,
    range: Range,
    context: CodeActionContext,
};

pub const CodeActionContext = struct {
    diagnostics: []Diagnostic,
    only: ?[]String = null,
};

pub const CodeAction = struct {
    title: String,
    kind: ?String = null,
    diagnostics: ?[]Diagnostic = null,
    isPreferred: ?bool = null,
    edit: ?WorkspaceEdit = null,
    command: ?Command = null,
};

pub const CodeLensParams = struct {
    textDocument: TextDocumentIdentifier,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const CodeLens = struct {
    range: Range,
    command: ?Command = null,
    // data: ?jsonic.AnyValue = null,
};

pub const DocumentLinkParams = struct {
    textDocument: TextDocumentIdentifier,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const DocumentLink = struct {
    range: Range,
    target: ?DocumentUri = null,
    toolTip: ?String = null,
    // data: ?jsonic.AnyValue = null,
};

pub const DocumentColorParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    textDocument: TextDocumentIdentifier,
};

pub const ColorInformation = struct {
    range: Range,
    color: Color,
};

pub const Color = struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};

pub const ColorPresentationParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    textDocument: TextDocumentIdentifier,
    color: Color,
    range: Range,
};

pub const ColorPresentation = struct {
    label: String,
    textEdit: ?TextEdit = null,
    additionalTextEdits: ?[]TextEdit = null,
};

pub const DocumentFormattingParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    textDocument: TextDocumentIdentifier,
    options: FormattingOptions,
};

pub const FormattingOptions = struct {
    tabSize: isize,
    insertSpaces: bool,
    trimTrailingWhitespace: ?bool = null,
    insertFinalNewline: ?bool = null,
    trimFinalNewlines: ?bool = null,
};

pub const DocumentRangeFormattingParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    textDocument: TextDocumentIdentifier,
    range: Range,
    options: FormattingOptions,
};

pub const DocumentOnTypeFormattingParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    ch: String,
    options: FormattingOptions,
};

pub const DocumentOnTypeFormattingRegistrationOptions = struct {
    TextDocumentRegistrationOptions: TextDocumentRegistrationOptions,
    firstTriggerCharacter: String,
    moreTriggerCharacter: ?[]String = null,
};

pub const RenameParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    newName: String,
};

pub const FoldingRangeParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    textDocument: TextDocumentIdentifier,
};

pub const FoldingRange = struct {
    startLine: isize,
    startCharacter: ?isize = null,
    endLine: isize,
    endCharacter: ?isize = null,
    kind: ?String = null,

    pub const Kind = struct {
        pub const Comment = "comment";
        pub const Imports = "imports";
        pub const Region = "region";
    };
};

pub const SignatureHelpParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    context: ?SignatureHelpContext = null,
};

pub const WorkDoneProgressParams = struct {
    workDoneToken: ?ProgressToken = null,
};

pub const WorkDoneProgressCancelParams = struct {
    token: ProgressToken,
};

pub const PartialResultParams = struct {
    partialResultToken: ?ProgressToken = null,
};

pub const ProgressToken = jsonic.AnyValue;

pub const ProgressParams = struct {
    token: ProgressToken,
    value: jsonic.AnyValue,
};

pub const WorkDoneProgress = struct {
    kind: String,
    title: String,
    cancellable: ?bool = null,
    message: ?String = null,
    percentage: ?isize = null,

    pub const Kind = struct {
        pub const Begin = "begin";
        pub const Report = "report";
        pub const End = "end";
    };
};

pub const SignatureHelpContext = struct {
    triggerKind: ?SignatureHelpTriggerKind = null,
    triggerCharacter: ?String = null,
    isRetrigger: bool,
    activeSignatureHelp: ?SignatureHelp = null,
};

pub const SignatureHelpTriggerKind = enum {
    Invoked = 1,
    TriggerCharacter = 2,
    ContentChange = 3,
};

pub const HoverParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
};

pub const DeclarationParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const DefinitionParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const TypeDefinitionParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const ImplementationParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const DocumentHighlightParams = struct {
    TextDocumentPositionParams: TextDocumentPositionParams,
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
};

pub const SelectionRange = struct {
    range: Range,
    parent: ?*SelectionRange = null,
};

pub const SelectionRangeParams = struct {
    WorkDoneProgressParams: WorkDoneProgressParams,
    PartialResultParams: PartialResultParams,
    textDocument: TextDocumentIdentifier,
    positions: []Position,
};

pub const WorkDoneProgressCreateParams = struct {
    token: ProgressToken,
};
