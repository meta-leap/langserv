usingnamespace @import("./_usingnamespace.zig");

pub fn setupWorkspaceFolderAndFileRelatedCapabilitiesAndHandlers(srv: *Server) void {
    srv.cfg.capabilities.textDocumentSync = .{
        .options = .{
            .openClose = true,
            .change = TextDocumentSyncKind.Incremental,
            .save = .{ .includeText = true },
        },
    };
    srv.api.onNotify(.textDocument_didClose, onFileClosed);
    srv.api.onNotify(.textDocument_didOpen, onFileBufOpened);
    srv.api.onNotify(.textDocument_didChange, onFileBufEdited);
    srv.api.onNotify(.textDocument_didSave, onFileBufSaved);
    srv.api.onNotify(.workspace_didChangeWorkspaceFolders, onDirEvent);
    srv.api.onNotify(.workspace_didChangeWatchedFiles, onFileEvents);
}

pub fn onDirEvent(ctx: Server.Ctx(DidChangeWorkspaceFoldersParams)) !void {
    try onDirsEncountered(ctx.inst, ctx.mem, "", ctx.value.event.added, ctx.value.event.removed);
}

fn onDirsEncountered(srv: *Server, mem: *std.mem.Allocator, workspace_folder_uri: Str, workspace_folders: []WorkspaceFolder, more_workspace_folders: []WorkspaceFolder) !void {
    if (workspace_folder_uri.len == 0 and workspace_folders.len == 0)
        return;

    var dir_paths = try std.ArrayList(SrcFiles.EnsureTracked).initCapacity(mem, 1 + workspace_folders.len + more_workspace_folders.len);
    if (workspace_folder_uri.len > 0)
        try dir_paths.append(.{ .absolute_path = lspUriToFilePath(workspace_folder_uri) });
    for (workspace_folders) |*workspace_folder|
        try dir_paths.append(.{ .absolute_path = lspUriToFilePath(workspace_folder.uri) });
    for (more_workspace_folders) |*workspace_folder|
        try dir_paths.append(.{ .absolute_path = lspUriToFilePath(workspace_folder.uri) });
    try zsess.workers.src_files_gatherer.base.enqueueJobs(dir_paths.toSliceConst());
}

pub fn onFileBufOpened(ctx: Server.Ctx(DidOpenTextDocumentParams)) error{}!void {
    std.debug.warn("\nonFileBufOpened\t{}\t{}\n", .{ lspUriToFilePath(ctx.value.textDocument.uri), ctx.value.textDocument.languageId });
}

pub fn onFileClosed(ctx: Server.Ctx(DidCloseTextDocumentParams)) !void {
    try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
        .{ .absolute_path = lspUriToFilePath(ctx.value.textDocument.uri) },
    });
}

pub fn onFileBufEdited(ctx: Server.Ctx(DidChangeTextDocumentParams)) error{}!void {
    //
}

pub fn onFileBufSaved(ctx: Server.Ctx(DidSaveTextDocumentParams)) error{}!void {
    //
}

pub fn onFileEvents(ctx: Server.Ctx(DidChangeWatchedFilesParams)) error{}!void {
    //
}

pub fn onInitRegisterFileWatcherAndProcessWorkspaceFolders(ctx: Server.Ctx(InitializedParams)) !void {
    try ctx.inst.api.request(.client_registerCapability, {}, RegistrationParams{
        .registrations = &[1]Registration{Registration{
            .method = "workspace/didChangeWatchedFiles",
            .id = try zag.util.uniqueishId(ctx.mem, "ziglangserver_filewatch"),
            .registerOptions = try jsonic.AnyValue.fromStd(ctx.mem, &(try jsonrpc_options.json.marshal(ctx.mem, DidChangeWatchedFilesRegistrationOptions{
                .watchers = &[1]FileSystemWatcher{
                    FileSystemWatcher{
                        .globPattern = "**/*.zig",
                    },
                },
            }))),
        }},
    }, struct {
        pub fn then(state: void, resp: Server.Ctx(Result(void))) error{}!void {
            logToStderr("File-watcher registration: {}\n", .{resp.value});
        }
    });

    try onDirsEncountered(
        ctx.inst,
        ctx.mem,
        ctx.inst.initialized.?.rootUri orelse "",
        ctx.inst.initialized.?.workspaceFolders orelse &[_]WorkspaceFolder{},
        &[_]WorkspaceFolder{},
    );
}
