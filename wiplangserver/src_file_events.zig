usingnamespace @import("./_usingnamespace.zig");

pub fn onDirsAdded(srv: *Server, mem: *std.mem.Allocator, workspace_folder_uri: Str, workspace_folders: []WorkspaceFolder) !void {
    if (workspace_folder_uri.len == 0 and workspace_folders.len == 0)
        return;

    var dir_paths = try std.ArrayList(WorkerSrcFilesGatherer.Job).initCapacity(mem, 1 + workspace_folders.len);
    if (workspace_folder_uri.len > 0)
        try dir_paths.append(.{ .full_path = std.mem.trimLeft(u8, workspace_folder_uri, "file://"), .event_kind = .dir_added });
    for (workspace_folders) |*workspace_folder|
        try dir_paths.append(.{ .full_path = std.mem.trimLeft(u8, workspace_folder.uri, "file://"), .event_kind = .dir_added });
    try zsess.workers.src_files_gatherer.base.enqueueJobs(dir_paths.toSliceConst());
}

pub fn onDirEvent(ctx: Server.Ctx(DidChangeWorkspaceFoldersParams)) !void {
    try onDirsAdded(ctx.inst, ctx.mem, "", ctx.value.event.added);
}

pub fn onFileBufOpened(ctx: Server.Ctx(DidOpenTextDocumentParams)) error{}!void {
    //
}

pub fn onFileClosed(ctx: Server.Ctx(DidCloseTextDocumentParams)) error{}!void {
    //
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
