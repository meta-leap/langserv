usingnamespace @import("./_usingnamespace.zig");

pub var src_files_owned_by_client: struct {
    live_bufs: std.BufMap,
    versions: std.AutoHashMap(u64, ?isize),
    mutex: std.Mutex = std.Mutex.init(),

    pub fn lock(me: *@This()) std.Mutex.Held {
        return me.mutex.acquire();
    }

    pub fn init(me: *@This()) void {
        me.live_bufs = std.BufMap.init(mem_alloc);
        me.versions = std.AutoHashMap(u64, ?isize).init(mem_alloc);
    }

    pub fn deinit(me: *@This()) void {
        me.live_bufs.deinit();
        me.versions.deinit();
    }
} = undefined;

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
    const src_file_id = SrcFile.id(src_file_abs_path);
    {
        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        try src_files_owned_by_client.live_bufs.set(src_file_abs_path, ctx.value.textDocument.text);
        if (try src_files_owned_by_client.versions.put(src_file_id, ctx.value.textDocument.version)) |existed_already|
            _ = try src_files_owned_by_client.versions.put(src_file_id, null);
    }
    try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_refresh = false,
        },
    });
}

pub fn onFileClosed(ctx: Server.Ctx(DidCloseTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    const src_file_id = SrcFile.id(src_file_abs_path);
    {
        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        src_files_owned_by_client.live_bufs.delete(src_file_abs_path);
        _ = src_files_owned_by_client.versions.remove(src_file_id);
    }
    try zsess.workers.src_files_gatherer.base.enqueueJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_refresh = false,
        },
    });
}

pub fn onFileBufEdited(ctx: Server.Ctx(DidChangeTextDocumentParams)) !void {
    const lock = src_files_owned_by_client.lock();
    var should_refresh = false;
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.TextDocumentIdentifier.uri);
    defer {
        lock.release();
        if (should_refresh)
            if (zsess.src_files.getByFullPath(src_file_abs_path)) |src_file|
                src_file.refresh() catch {};
    }
    const src_file_id = SrcFile.id(src_file_abs_path);

    if (src_files_owned_by_client.live_bufs.get(src_file_abs_path)) |cur_src| {
        if (ctx.value.contentChanges.len > 0) {
            var buf_len: usize = cur_src.len;
            var capacity = buf_len;
            for (ctx.value.contentChanges) |*change|
                capacity += change.text.len;
            var buf = try ctx.mem.alloc(u8, capacity);
            std.mem.copy(u8, buf[0..buf_len], cur_src);
            for (ctx.value.contentChanges) |*change| {
                const start_end = if (change.range) |range|
                    ((range.sliceBounds(buf[0..buf_len]) catch |err| {
                        src_files_owned_by_client.live_bufs.delete(src_file_abs_path);
                        _ = src_files_owned_by_client.versions.remove(src_file_id);
                        return;
                    }) orelse {
                        src_files_owned_by_client.live_bufs.delete(src_file_abs_path);
                        _ = src_files_owned_by_client.versions.remove(src_file_id);
                        return;
                    })
                else
                    [2]usize{ 0, buf_len };
                buf_len = zag.mem.edit(buf, buf_len, start_end[0], start_end[1], change.text);
            }
            // std.debug.warn("\n\nNEWSRC:>>>>>{}<<<<<<<<\n\n", .{buf[0..buf_len]});
            try src_files_owned_by_client.live_bufs.set(src_file_abs_path, buf[0..buf_len]);
            should_refresh = true;
        }
    } else {
        src_files_owned_by_client.live_bufs.delete(src_file_abs_path);
        _ = src_files_owned_by_client.versions.remove(src_file_id);
        return;
    }
    if (ctx.value.textDocument.version) |new_version|
        if (src_files_owned_by_client.versions.get(src_file_id)) |old_version| {
            if (old_version.value != null) // improves correctness in case of buggy / non-spec-conformant clients, see onFileBufOpened
                _ = try src_files_owned_by_client.versions.put(src_file_id, new_version);
        };
}

pub fn onFileBufSaved(ctx: Server.Ctx(DidSaveTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    if (ctx.value.text) |src_bytes| {
        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        try src_files_owned_by_client.live_bufs.set(src_file_abs_path, src_bytes);
    }
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
        const currently_owned_by_client = check: {
            const lock = src_files_owned_by_client.lock();
            defer lock.release();
            break :check (null != src_files_owned_by_client.live_bufs.get(src_file_abs_path));
        };
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

pub fn loadSrcFileEitherFromFsOrFromLiveBufCache(mem: *std.mem.Allocator, src_file_abs_path: Str) !Str {
    const src_live: ?Str = check: {
        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        break :check src_files_owned_by_client.live_bufs.get(src_file_abs_path);
    };
    if (src_live) |src|
        return try std.mem.dupe(mem, u8, src)
    else
        return try SrcFile.defaultLoadFromPath(mem, src_file_abs_path);
}
