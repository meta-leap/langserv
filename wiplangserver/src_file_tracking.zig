usingnamespace @import("./_usingnamespace.zig");

const sync_kind = TextDocumentSyncKind.Full;

pub var src_files_watcher_active = false;
var had_file_bufs_opened_event_yet = false;

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

pub fn setupSrcFileAndWorkFolderRelatedCapabilitiesAndHandlers(srv: *Server) void {
    srv.cfg.capabilities.textDocumentSync = .{
        .options = .{
            .openClose = true,
            .change = sync_kind,
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
        try dir_paths.append(.{ .is_dir = true, .absolute_path = lspUriToFilePath(workspace_folder_uri) });
    for (workspace_folders) |*workspace_folder|
        try dir_paths.append(.{ .is_dir = true, .absolute_path = lspUriToFilePath(workspace_folder.uri) });
    for (more_workspace_folders) |*workspace_folder|
        try dir_paths.append(.{ .is_dir = true, .absolute_path = lspUriToFilePath(workspace_folder.uri) });
    try zsess.workers.src_files_gatherer.base.appendJobs(dir_paths.toSliceConst());
}

pub fn onFileBufOpened(ctx: Server.Ctx(DidOpenTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    const src_file_id = SrcFile.id(src_file_abs_path);
    zsess.workers.src_files_refresh_intel.base.cancelPendingEnqueuedJob(src_file_id);
    zsess.workers.src_files_reloader.base.cancelPendingEnqueuedJob(src_file_id);
    {
        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        try src_files_owned_by_client.live_bufs.set(src_file_abs_path, ctx.value.textDocument.text);
        if (try src_files_owned_by_client.versions.put(src_file_id, ctx.value.textDocument.version)) |existed_already|
            _ = try src_files_owned_by_client.versions.put(src_file_id, null);
    }

    var todo = &[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_reload = true,
        },
    };
    if (had_file_bufs_opened_event_yet)
        try zsess.workers.src_files_gatherer.base.prependJobs(todo)
    else { // fast-track the very first one as it's the currently-opened buffer on session start
        try zsess.src_files.ensureFilesTracked(ctx.memArena(), todo);
        had_file_bufs_opened_event_yet = true;
    }
}

pub fn onFileClosed(ctx: Server.Ctx(DidCloseTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    const src_file_id = SrcFile.id(src_file_abs_path);
    zsess.workers.src_files_refresh_intel.base.cancelPendingEnqueuedJob(src_file_id);
    zsess.workers.src_files_reloader.base.cancelPendingEnqueuedJob(src_file_id);
    {
        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        src_files_owned_by_client.live_bufs.delete(src_file_abs_path);
        _ = src_files_owned_by_client.versions.remove(src_file_id);
    }
    try zsess.workers.src_files_gatherer.base.prependJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_reload = true,
        },
    });
}

pub fn onFileBufEdited(ctx: Server.Ctx(DidChangeTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.TextDocumentIdentifier.uri);
    const lock = src_files_owned_by_client.lock();
    const cur_src = src_files_owned_by_client.live_bufs.get(src_file_abs_path) orelse {
        lock.release();
        return;
    };
    defer {
        lock.release();
        if (zsess.src_files.getByFullPath(src_file_abs_path)) |src_file| {
            src_file.reload(ctx.memArena()) catch {};
            zsess.workers.src_files_refresh_intel.base.prependJobs(&[_]u64{src_file.id}) catch {};
        }
    }
    const src_file_id = SrcFile.id(src_file_abs_path);
    zsess.workers.src_files_reloader.base.cancelPendingEnqueuedJob(src_file_id);
    zsess.workers.src_files_refresh_intel.base.cancelPendingEnqueuedJob(src_file_id);
    var drop_from_live_mode = false;
    actual_work: {
        if (ctx.value.contentChanges.len == 0)
            return;
        if (sync_kind == .Full)
            try src_files_owned_by_client.live_bufs.set(src_file_abs_path, ctx.value.
                contentChanges[ctx.value.contentChanges.len - 1].text)
        else if (sync_kind == .Incremental) {
            var buf_len: usize = cur_src.len;
            var capacity = buf_len;
            for (ctx.value.contentChanges) |*change|
                capacity += change.text.len;
            var buf = try ctx.mem.alloc(u8, capacity);
            std.mem.copy(u8, buf[0..buf_len], cur_src);
            for (ctx.value.contentChanges) |*change| {
                const start_end = if (change.range) |range|
                    ((range.sliceBounds(buf[0..buf_len]) catch |err| {
                        drop_from_live_mode = true;
                        break :actual_work;
                    }) orelse {
                        drop_from_live_mode = true;
                        break :actual_work;
                    })
                else
                    [2]usize{ 0, buf_len };
                buf_len = zag.mem.edit(buf, buf_len, start_end[0], start_end[1], change.text);
            }
            // logToStderr("\n\nNEWSRC:>>>>>{}<<<<<<<<\n\n", .{buf[0..buf_len]});
            try src_files_owned_by_client.live_bufs.set(src_file_abs_path, buf[0..buf_len]);
        } else
            unreachable;

        var versions_botched = (sync_kind != .Full);
        if (ctx.value.textDocument.version) |new_version|
            if (src_files_owned_by_client.versions.getValue(src_file_id)) |maybe_old_version|
                if (maybe_old_version) |old_version| {
                    if (sync_kind == .Full or new_version == old_version + 1) {
                        versions_botched = false;
                        _ = try src_files_owned_by_client.versions.put(src_file_id, new_version);
                    }
                };
        if (versions_botched)
            drop_from_live_mode = true;
    }
    if (drop_from_live_mode) {
        src_files_owned_by_client.live_bufs.delete(src_file_abs_path);
        _ = src_files_owned_by_client.versions.remove(src_file_id);
        try ctx.inst.api.notify(.window_showMessage, ShowMessageParams{
            .@"type" = .Warning,
            .message = try std.fmt.allocPrint(ctx.mem, "No longer in live mode for {s}. Until re-opening, all intel will be from the on-disk file. Please report to github.com/meta-leap/langserv with details about your LSP client.", .{src_file_abs_path}),
        });
    }
}

pub fn onFileBufSaved(ctx: Server.Ctx(DidSaveTextDocumentParams)) !void {
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);
    if (ctx.value.text) |new_src| {
        const src_file_id = SrcFile.id(src_file_abs_path);
        zsess.workers.src_files_reloader.base.cancelPendingEnqueuedJob(src_file_id);
        zsess.workers.src_files_refresh_intel.base.cancelPendingEnqueuedJob(src_file_id);

        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        if (src_files_owned_by_client.live_bufs.get(src_file_abs_path)) |_|
            try src_files_owned_by_client.live_bufs.set(src_file_abs_path, new_src);
    }
    try zsess.workers.src_files_gatherer.base.prependJobs(&[_]SrcFiles.EnsureTracked{
        .{
            .absolute_path = src_file_abs_path,
            .force_reload = !src_files_watcher_active,
        },
    });
}

pub fn onFileEvents(ctx: Server.Ctx(DidChangeWatchedFilesParams)) !void {
    var src_file_ids = try ctx.mem.alloc(u64, ctx.value.changes.len);
    var src_file_abs_paths = try ctx.mem.alloc(Str, ctx.value.changes.len);
    for (ctx.value.changes) |_, i| {
        src_file_abs_paths[i] = lspUriToFilePath(ctx.value.changes[i].uri);
        src_file_ids[i] = SrcFile.id(src_file_abs_paths[i]);
    }
    zsess.workers.src_files_reloader.base.cancelPendingEnqueuedJobs(src_file_ids);
    zsess.workers.src_files_refresh_intel.base.cancelPendingEnqueuedJobs(src_file_ids);
    var jobs = try std.ArrayList(SrcFiles.EnsureTracked).initCapacity(ctx.mem, ctx.value.changes.len);
    var gone = try std.ArrayList(Str).initCapacity(ctx.mem, ctx.value.changes.len);
    {
        const lock = src_files_owned_by_client.lock();
        defer lock.release();
        for (ctx.value.changes) |file_event, i| {
            const currently_owned_by_client = (null != src_files_owned_by_client.live_bufs.get(src_file_abs_paths[i]));
            if (file_event.@"type" == .Deleted)
                try gone.append(src_file_abs_paths[i])
            else
                try jobs.append(.{ .absolute_path = src_file_abs_paths[i], .force_reload = !currently_owned_by_client });
        }
    }
    if (jobs.len != 0)
        try zsess.workers.src_files_gatherer.base.appendJobs(jobs.toSlice());
    if (gone.len != 0)
        try zsess.src_files.ensureFilesGone(ctx.memArena(), gone.toSliceConst());
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
            switch (resp.value) {
                .ok => src_files_watcher_active = true,
                .err => |err| logToStderr("Requested file-watcher rejected: {}\n", .{err}),
            }
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
