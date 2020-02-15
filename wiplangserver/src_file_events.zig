usingnamespace @import("./_usingnamespace.zig");

pub var src_files_owned_by_client: std.BufMap = undefined;

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

pub fn onFileBufOpened(ctx: Server.Ctx(DidOpenTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    try src_files_owned_by_client.set(src_file_abs_path, ctx.value.textDocument.text);
    try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_refresh = true,
        },
    });
}

pub fn onFileBufEdited(ctx: Server.Ctx(DidChangeTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.TextDocumentIdentifier.uri);
    try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_refresh = true,
        },
    });
}

pub fn onFileClosed(ctx: Server.Ctx(DidCloseTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    src_files_owned_by_client.delete(src_file_abs_path);
    try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_refresh = true,
        },
    });
}

pub fn onFileBufSaved(ctx: Server.Ctx(DidSaveTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    if (ctx.value.text) |src_bytes|
        try src_files_owned_by_client.set(src_file_abs_path, src_bytes);
    try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_refresh = (ctx.value.text != null),
        },
    });
}

pub fn onFileEvents(ctx: Server.Ctx(DidChangeWatchedFilesParams)) !void {
    for (ctx.value.changes) |file_event| {
        const src_file_abs_path = lspUriToFilePath(file_event.uri);
        const currently_owned_by_client = (null != src_files_owned_by_client.get(src_file_abs_path));
        try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
            .{ .absolute_path = src_file_abs_path, .force_refresh = !currently_owned_by_client },
        });
    }
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

pub fn loadSrcFileFromPath(mem: *std.mem.Allocator, src_file_abs_path: Str) !Str {
    return SrcFile.defaultLoadFromPath(mem, src_file_abs_path);
}
