usingnamespace @import("./_usingnamespace.zig");

pub const Session = struct {
    mem_alloc: *std.mem.Allocator = undefined,
    inited: bool = false,
    tmp_work_dir: ?zag.fs.TmpDir = null,
    src_files: SrcFiles = undefined,
    src_intel: SrcIntel = undefined,
    workers: struct {
        src_files_gatherer: WorkerSrcFilesGatherer = WorkerSrcFilesGatherer{},
        src_files_reloader: WorkerSrcFilesReload = WorkerSrcFilesReload{},
        src_files_refresh_imports: WorkerSrcFilesRefreshImports = WorkerSrcFilesRefreshImports{},
        issues_announcer: WorkerIssuesGathererAndAnnouncer = WorkerIssuesGathererAndAnnouncer{},
        deps_syncer: WorkerSrcFileDepsSyncer = WorkerSrcFileDepsSyncer{},
        build_runs: WorkerBuildRuns = WorkerBuildRuns{},
    } = undefined,
    zig_install: struct {
        mutex: std.Mutex = std.Mutex.init(),
        exe_path: ?Str = null,
        std_lib_dir_path: ?Str = null,
        langref_html_file_path: ?Str = null,
        langref_html_file_src: ?Str = null,

        pub fn stdLibDirPath(me: *@This()) ?Str {
            const lock = me.mutex.acquire();
            defer lock.release();
            return me.std_lib_dir_path;
        }

        pub fn exePath(me: *const @This()) Str {
            return me.exe_path orelse "zig";
        }

        pub fn exeDirPathGuess(me: *@This()) ?Str {
            if (std.fs.path.dirname(me.exePath())) |dir|
                return dir;
            if (me.stdLibDirPath()) |somewhere_lib_zig_std|
                if (std.fs.path.dirname(somewhere_lib_zig_std)) |somewhere_lib_zig|
                    if (std.fs.path.dirname(somewhere_lib_zig)) |somewhere_lib|
                        return std.fs.path.dirname(somewhere_lib); // -> somewhere
            return null;
        }

        pub fn langrefHtmlFilePathGuess(me: *@This()) ?Str {
            if (null == me.langref_html_file_path)
                if (me.exeDirPathGuess()) |exe_dir_path| {
                    const sess: *Session = @fieldParentPtr(Session, "zig_install", me);
                    me.langref_html_file_path = std.fs.path.join(sess.mem_alloc, &[_]Str{ exe_dir_path, "langref.html" }) catch return null;
                };
            return me.langref_html_file_path;
        }

        pub fn langrefHtmlFileSrc(me: *@This()) ?Str {
            if (null == me.langref_html_file_src)
                if (me.langrefHtmlFilePathGuess()) |langref_html_file_path| {
                    const sess: *Session = @fieldParentPtr(Session, "zig_install", me);
                    me.langref_html_file_src = std.fs.cwd().readFileAlloc(sess.
                        mem_alloc, langref_html_file_path, @as(usize, 1024 * 1024 * 1024)) catch return null;
                };
            return me.langref_html_file_src;
        }

        pub fn langrefHtmlFileSrcSnippet(me: *@This(), mem_temp: *std.heap.ArenaAllocator, needle: Str) !?Str {
            const langref_html_src = me.langrefHtmlFileSrc() orelse return null;
            const indices = (try me.langrefHtmlFileSrcIndices(mem_temp, needle)) orelse return null;
            return langref_html_src[indices[0]..indices[1]];
        }

        pub fn langrefHtmlFileSrcRange(me: *@This(), mem_temp: *std.heap.ArenaAllocator, needle: Str) !?[]usize {
            const langref_html_src = me.langrefHtmlFileSrc() orelse return null;
            return try SrcIntel.convertPosInfoToCustom(mem_temp, langref_html_src, false, (try me.
                langrefHtmlFileSrcIndices(mem_temp, needle)) orelse return null, .byte_offsets_0_based_range);
        }

        pub fn langrefHtmlFileSrcIndices(me: *@This(), mem_temp: *std.heap.ArenaAllocator, needle: Str) !?[2]usize {
            const langref_html_src = me.langrefHtmlFileSrc() orelse return null;
            const idx = std.mem.indexOf(u8, langref_html_src, try std.fmt.
                allocPrint(&mem_temp.allocator, " id=\"{s}\"", .{needle})) orelse return null;
            const idx_p1 = std.mem.indexOfPos(u8, langref_html_src, idx, "<p>");
            const idx_p2 = if (idx_p1) |p_idx| std.mem.indexOfPos(u8, langref_html_src, p_idx, "</p>") else null;
            return if (idx_p1 != null and idx_p2 != null)
                [2]usize{ idx_p1.? + 3, idx_p2.? }
            else
                [2]usize{ idx + 5, idx + 5 + needle.len };
        }
    },

    pub fn initAndStart(me: *Session, mem_alloc: *std.mem.Allocator, shared_or_sys_tmp_root_dir_path: Str) !void {
        std.debug.assert(!me.inited);

        me.mem_alloc = mem_alloc;
        me.src_files = .{
            .sess = me,
            .issues = std.StringHashMap([]SrcFiles.Issue).init(me.mem_alloc),
            .files = std.AutoHashMap(u64, *SrcFile).init(me.mem_alloc),
            .build_zig_dir_paths = std.StringHashMap(void).init(me.mem_alloc),
        };
        try me.src_files.files.ensureCapacity(1024);
        me.src_intel = .{ .sess = me };

        me.inited = true;
        me.workers = .{};
        try me.workers.issues_announcer.base.initAndSpawn(me);
        try me.workers.src_files_refresh_imports.base.initAndSpawn(me);
        try me.workers.src_files_reloader.base.initAndSpawn(me);
        try me.workers.src_files_gatherer.base.initAndSpawn(me);
        try me.workers.deps_syncer.base.initAndSpawn(me);
        try me.workers.build_runs.base.initAndSpawn(me);

        if (try zag.fs.TmpDir.init(me.mem_alloc, shared_or_sys_tmp_root_dir_path, "ziglsp", "sess", true)) |tmp_dir|
            me.tmp_work_dir = tmp_dir;
    }

    pub fn stopAndDeinit(me: *Session) void {
        if (me.inited) {
            me.inited = false; // ongoing threads check on this in their loops and abort themselves

            // we don't self-destruct until all threads aborted
            me.workers.src_files_gatherer.base.thread.wait();
            me.workers.src_files_reloader.base.thread.wait();
            me.workers.src_files_refresh_imports.base.thread.wait();
            me.workers.issues_announcer.base.thread.wait();
            me.workers.deps_syncer.base.thread.wait();
            me.workers.build_runs.base.thread.wait();

            me.src_intel.deinit();
            me.src_files.deinit();
            if (me.tmp_work_dir != null)
                me.tmp_work_dir.?.deinit(true);

            const lock = me.zig_install.mutex.acquire();
            defer lock.release();
            if (me.zig_install.std_lib_dir_path) |std_lib_dir_path|
                me.mem_alloc.free(std_lib_dir_path);
            if (me.zig_install.langref_html_file_path) |langref_html_file_path|
                me.mem_alloc.free(langref_html_file_path);
            if (me.zig_install.langref_html_file_src) |langref_html_file_src|
                me.mem_alloc.free(langref_html_file_src);
            if (me.zig_install.exe_path) |exe_path|
                me.mem_alloc.free(exe_path);
        }
    }

    pub fn cancelPendingEnqueuedSrcFileRefreshJobs(
        me: *Session,
        src_file_id: u64,
        cancel_reload: bool,
        cancel_refresh_imports: bool,
        cancel_issues_announcer: bool,
    ) void {
        var done: u2 = 0;
        var want: u2 = 0;
        if (cancel_reload) want += 1;
        if (cancel_refresh_imports) want += 1;
        if (cancel_issues_announcer) want += 1;
        var did_cancel_reload = false;
        var did_cancel_refresh_imports = false;
        var did_cancel_issues_announcer = false;
        while (done != want) {
            if (cancel_reload and !did_cancel_reload and me.workers.src_files_reloader.base.tryCancelPendingEnqueuedJob(src_file_id)) {
                done += 1;
                did_cancel_reload = true;
            }
            if (cancel_refresh_imports and !did_cancel_refresh_imports and me.workers.src_files_refresh_imports.base.tryCancelPendingEnqueuedJob(src_file_id)) {
                done += 1;
                did_cancel_refresh_imports = true;
            }
            if (cancel_issues_announcer and !did_cancel_issues_announcer and me.workers.issues_announcer.base.tryCancelPendingEnqueuedJob(src_file_id)) {
                done += 1;
                did_cancel_issues_announcer = true;
            }
        }
    }

    pub fn digForStdLibDirPathViaTempNewLibProj(me: *Session) void {
        if (me.tmp_work_dir) |*tmp_dir| {
            var mem_arena = std.heap.ArenaAllocator.init(me.mem_alloc);
            defer mem_arena.deinit();
            defer tmp_dir.cur_dir.deleteTree("zig-cache") catch {};
            const zig_std_lib_dir_path_maybe = digForStdLibDirPathViaTemporaryNewLibProj(&mem_arena, tmp_dir, me.
                zig_install.exePath(), "zig-cache");
            if (zig_std_lib_dir_path_maybe) |zig_std_lib_dir_path| {
                const long_lived_copy = std.mem.dupe(me.mem_alloc, u8, zig_std_lib_dir_path) catch return;
                {
                    const lock = me.zig_install.mutex.acquire();
                    defer lock.release();
                    me.zig_install.std_lib_dir_path = long_lived_copy;
                }
                me.workers.src_files_gatherer.base.appendJobs(&[_]SrcFiles.EnsureTracked{
                    .{ .absolute_path = zig_std_lib_dir_path, .is_dir = true },
                }) catch return;
                std.debug.warn("STDLIB\t{}\n", .{zig_std_lib_dir_path});
            }
        }
    }
};

fn digForStdLibDirPathViaTemporaryNewLibProj(mem_arena: *std.heap.ArenaAllocator, tmp_dir: *zag.fs.TmpDir, zig_exe_path: Str, comptime cache_dir_name: Str) ?Str {
    const cmd_ziginitlib = std.ChildProcess.exec(&mem_arena.allocator, &[_]Str{ zig_exe_path, "init-lib" }, null, null, std.math.maxInt(usize)) catch
        return null;
    if (cmd_ziginitlib.term != .Exited)
        return null;

    const cmd_zigbuildtest = std.ChildProcess.exec(&mem_arena.allocator, &[_]Str{ zig_exe_path, "build", "test", "--cache-dir", cache_dir_name }, null, null, std.math.maxInt(usize)) catch
        return null;
    if (cmd_zigbuildtest.term != .Exited)
        return null;

    var cache_h_dir = tmp_dir.cur_dir.openDirList(cache_dir_name ++ std.fs.path.sep_str ++ "h") catch
        return null;
    defer cache_h_dir.close();
    var iter = cache_h_dir.iterate();
    search: while (iter.next() catch return null) |entry| {
        if (entry.kind == .File and std.mem.endsWith(u8, entry.name, ".txt")) {
            var txt_file = cache_h_dir.openFile(entry.name, .{}) catch return null;
            defer txt_file.close();
            const txt_file_bytes = mem_arena.allocator.alloc(u8, (txt_file.stat() catch return null).size) catch
                |err| @panic(@errorName(err));
            _ = txt_file.inStream().stream.readFull(txt_file_bytes) catch return null;
            var pos: usize = 0;
            while (pos < txt_file_bytes.len) {
                const needle = std.fs.path.sep_str ++ "lib" ++ std.fs.path.sep_str ++ "zig" ++ std.fs.path.sep_str ++ "std" ++ std.fs.path.sep_str ++ "std.zig";
                if (std.mem.indexOfPos(u8, txt_file_bytes, pos, needle)) |idx| {
                    pos = idx + needle.len;
                    var i: usize = idx;
                    while (i > 0) : (i -= 1) if (std.fs.path.isAbsolute(txt_file_bytes[i..pos])) {
                        if (std.fs.openFileAbsolute(txt_file_bytes[i..pos], .{})) |file| {
                            file.close();
                            if (std.fs.path.dirname(txt_file_bytes[i..pos])) |dir_path|
                                return dir_path;
                        } else |_| {}
                    };
                } else
                    break;
            }
        }
    }
    return null;
}
