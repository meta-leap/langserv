usingnamespace @import("./_usingnamespace.zig");

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);

    // FILE EVENTS
    srv.cfg.capabilities.textDocumentSync = .{
        .options = .{
            .openClose = true,
            .change = TextDocumentSyncKind.Full,
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

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
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
                .err => |err| logToStderr("Failed to register for `workspace/didChangeWatchedFiles` notifications: {}\n", .{err}),
                else => logToStderr("Successfully registered for `workspace/didChangeWatchedFiles` notifications.\n", .{}),
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

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    return Result(void){ .ok = {} };
}
