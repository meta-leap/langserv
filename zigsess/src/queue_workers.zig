usingnamespace @import("./_usingnamespace.zig");

pub fn Worker(
    comptime TImpl: type,
    comptime TJob: type,
    comptime enqueue_deep_copies: bool,
    comptime initial_queue_capacity: usize,
    comptime accum_jobs_for_at_least_milliseconds: u64,
    comptime sleep_on_nothing_to_do_milliseconds: u64,
) type {
    return struct {
        sess: *Session = undefined,
        thread: *std.Thread = undefined,

        mutex: std.Mutex = std.Mutex.init(),
        time_last_enqueued: std.atomic.Int(u64) = std.atomic.Int(u64).init(0),
        jobs_queue: std.ArrayList(TJob) = undefined,

        pub fn initAndSpawn(me: *@This(), session: *Session) !void {
            me.sess = session;
            me.jobs_queue = try std.ArrayList(TJob).initCapacity(me.sess.mem_alloc, initial_queue_capacity);
            me.thread = try std.Thread.spawn(me, @This().forever);
        }

        pub inline fn shouldAbort(me: *@This()) bool {
            return !me.sess.inited;
        }

        pub fn forever(me: *@This()) void {
            defer {
                me.jobs_queue.deinit();
                if (@hasDecl(TImpl, "deinit"))
                    @fieldParentPtr(TImpl, "base", me).deinit();
            }

            while (me.sess.inited) {
                var time_last_enqueued = me.time_last_enqueued.get();
                if (time_last_enqueued == 0 or
                    std.time.milliTimestamp() - time_last_enqueued < accum_jobs_for_at_least_milliseconds)
                {
                    std.time.sleep(sleep_on_nothing_to_do_milliseconds * std.time.millisecond);
                } else {
                    me.time_last_enqueued.set(0);
                    me.fetchAndWorkPendingJobs() catch
                        |err| std.debug.panic("\n\n" ++ @typeName(TImpl) ++ ".base.fetchAndWorkPendingJobs fatal failure: {}\n\n", .{err});
                }
            }
            return;
        }

        fn fetchAndWorkPendingJobs(me: *@This()) !void {
            var jobs_queue: []TJob = &[_]TJob{};
            {
                const lock = me.mutex.acquire();
                defer lock.release();
                if (me.jobs_queue.len == 0)
                    return;
                jobs_queue = try std.mem.dupe(me.sess.mem_alloc, TJob, me.jobs_queue.toSliceConst());
                me.jobs_queue.len = 0;
            }
            defer if (enqueue_deep_copies)
                zag.mem.fullDeepFreeFrom(me.sess.mem_alloc, jobs_queue)
            else
                me.sess.mem_alloc.free(jobs_queue);

            var mem_temp = std.heap.ArenaAllocator.init(me.sess.mem_alloc);
            defer mem_temp.deinit();

            var jobs_deduped = try std.ArrayList(TJob).initCapacity(&mem_temp.allocator, jobs_queue.len);
            for (jobs_queue) |job, i|
                if (null == zag.mem.reoccursLater(jobs_queue, i, null))
                    try jobs_deduped.append(job);
            try @fieldParentPtr(TImpl, "base", me).
                workPendingJobs(&mem_temp, jobs_deduped.toSliceConst());
        }

        pub inline fn appendJobs(me: *@This(), job_entries: []const TJob) !void {
            return me.enqueue(job_entries, .low);
        }

        pub inline fn prependJobs(me: *@This(), job_entries: []const TJob) !void {
            return me.enqueue(job_entries, .high);
        }

        fn enqueue(me: *@This(), job_entries: []const TJob, prio: enum { high, low }) !void {
            if (job_entries.len == 0)
                return;
            const slice = if (!enqueue_deep_copies)
                job_entries
            else
                try zag.mem.fullDeepCopyTo(me.sess.mem_alloc, job_entries);

            defer if (enqueue_deep_copies)
                me.sess.mem_alloc.free(slice);

            const lock = me.mutex.acquire();
            defer lock.release();
            switch (prio) {
                .high => try me.jobs_queue.insertSlice(0, slice),
                .low => try me.jobs_queue.appendSlice(slice),
            }
            me.time_last_enqueued.set(std.time.milliTimestamp());
        }

        pub fn tryCancelPendingEnqueuedJob(me: *@This(), job: TJob) bool {
            if (me.mutex.tryAcquire()) |lock| {
                var removed: ?TJob = null;
                {
                    defer lock.release();
                    if (zag.mem.indexOf(me.jobs_queue.items[0..me.jobs_queue.len], job, 0, null)) |idx|
                        removed = me.jobs_queue.swapRemove(idx);
                }
                if (enqueue_deep_copies)
                    zag.mem.fullDeepFreeFrom(me.sess.mem_alloc, removed);
                return true;
            }
            return false;
        }

        pub fn cancelPendingEnqueuedJob(me: *@This(), job: TJob) void {
            while (!me.tryCancelPendingEnqueuedJob(job))
                std.time.sleep(123 * std.time.nanosecond);
        }

        pub fn cancelPendingEnqueuedJobs(me: *@This(), jobs: []const TJob) void {
            const lock = me.mutex.acquire();
            defer lock.release();
            for (jobs) |_, i| {
                if (zag.mem.indexOf(me.jobs_queue.items[0..me.jobs_queue.len], jobs[i], 0, null)) |idx| {
                    if (enqueue_deep_copies)
                        zag.mem.fullDeepFreeFrom(me.sess.mem_alloc, me.jobs_queue.swapRemove(idx))
                    else
                        _ = me.jobs_queue.swapRemove(idx);
                }
            }
        }
    };
}

pub const WorkerSrcFilesGatherer = struct {
    base: Base = Base{},
    const Base = Worker(WorkerSrcFilesGatherer, SrcFiles.EnsureTracked, true, 1024, 42, 42);

    fn workPendingJobs(me: *WorkerSrcFilesGatherer, mem_temp: *std.heap.ArenaAllocator, jobs_queue: []const SrcFiles.EnsureTracked) !void {
        const fileNameOk = struct {
            fn fileNameOk(file_name: Str) bool {
                return std.mem.endsWith(u8, file_name, ".zig");
            }
        }.fileNameOk;

        const seems_like_src_files = fileNameOk(jobs_queue[0].absolute_path);
        var src_file_jobs = try std.ArrayList(SrcFiles.EnsureTracked).initCapacity(
            &mem_temp.allocator,
            if (seems_like_src_files) jobs_queue.len else 512,
        );
        for (jobs_queue) |job| {
            if (me.base.shouldAbort())
                return;
            if (job.is_dir)
                _ = try zag.fs.gatherAllFiles(SrcFiles.EnsureTracked, "absolute_path", &src_file_jobs, job.absolute_path, fileNameOk, struct {
                    fn dirNameOk(dir_name: Str) bool {
                        return dir_name.len != 0 and dir_name[0] != '.' and
                            !std.mem.endsWith(u8, dir_name, "zig-cache");
                    }
                }.dirNameOk)
            else if (fileNameOk(job.absolute_path) and
                zag.mem.indexOf(src_file_jobs.toSliceConst(), job, 0, null) == null)
                try src_file_jobs.append(job);
        }
        try me.base.sess.src_files.ensureFilesTracked(mem_temp, src_file_jobs.toSliceConst());
    }
};

pub const WorkerSrcFilesReload = struct {
    base: Base = Base{},
    const Base = Worker(WorkerSrcFilesReload, u64, false, 1024, 8, 11);

    fn workPendingJobs(me: *WorkerSrcFilesReload, mem_temp: *std.heap.ArenaAllocator, jobs_queue: []const u64) !void {
        me.base.sess.workers.src_files_refresh_imports.base.cancelPendingEnqueuedJobs(jobs_queue);
        var refr_ids = try std.ArrayList(u64).initCapacity(&mem_temp.allocator, jobs_queue.len);
        var src_files = try me.base.sess.src_files.getByIds(&mem_temp.allocator, jobs_queue);
        for (src_files) |maybe_src_file, i|
            if (maybe_src_file) |src_file| {
                if (me.base.shouldAbort())
                    return;
                _ = try src_file.reload(mem_temp);
                try refr_ids.append(src_file.id);
            };
        if (refr_ids.len != 0)
            try me.base.sess.workers.src_files_refresh_imports.base.appendJobs(refr_ids.toSlice());
    }
};

pub const WorkerSrcFilesRefreshImports = struct {
    base: Base = Base{},
    const Base = Worker(WorkerSrcFilesRefreshImports, u64, false, 32, 1, 11);

    fn workPendingJobs(me: *WorkerSrcFilesRefreshImports, mem_temp: *std.heap.ArenaAllocator, jobs_queue: []const u64) !void {
        var file_gather_jobs = std.StringHashMap(void).init(&mem_temp.allocator);
        var num_files_refreshed: usize = 0;
        var src_files = try me.base.sess.src_files.getByIds(&mem_temp.allocator, jobs_queue);
        for (src_files) |maybe_src_file| {
            const src_file = maybe_src_file orelse continue;
            if (try src_file.ensureDirectImportsInIntel(mem_temp)) {
                num_files_refreshed += 1;
                const lock = src_file.mutex.acquire();
                defer lock.release();
                const direct_imports = (src_file.intel orelse continue).direct_imports orelse continue;
                for (direct_imports) |src_file_absolute_path| {
                    if (src_file_absolute_path.len != 0)
                        _ = try file_gather_jobs.put(src_file_absolute_path, {});
                }
            }
        }

        if (file_gather_jobs.count() != 0) {
            var jobs = try mem_temp.allocator.alloc(SrcFiles.EnsureTracked, file_gather_jobs.count());
            var iter = file_gather_jobs.iterator();
            var i: usize = 0;
            while (iter.next()) |entry| : (i += 1)
                jobs[i] = SrcFiles.EnsureTracked{ .absolute_path = entry.key };
            try me.base.sess.src_files.ensureFilesTracked(mem_temp, jobs);
        }

        if (num_files_refreshed != 0 and !me.base.shouldAbort())
            try me.base.sess.workers.deps_syncer.base.appendJobs(&[_]u1{undefined});
    }
};

pub const WorkerIssuesGathererAndAnnouncer = struct {
    base: Base = Base{},
    const Base = Worker(WorkerIssuesGathererAndAnnouncer, u64, false, 32, 42, 42);

    fn workPendingJobs(me: *WorkerIssuesGathererAndAnnouncer, mem_temp: *std.heap.ArenaAllocator, jobs_queue: []const u64) !void {
        return me.base.sess.src_files.reGatherIssues(mem_temp, jobs_queue);
    }
};

pub const WorkerSrcFileDepsSyncer = struct {
    base: Base = Base{},
    const Base = Worker(WorkerSrcFileDepsSyncer, u1, false, 8, 321, 321);

    fn workPendingJobs(me: *WorkerSrcFileDepsSyncer, mem_temp: *std.heap.ArenaAllocator, _: []const u1) !void {
        var importers = std.StringHashMap(*std.StringHashMap(void)).init(&mem_temp.allocator);

        const src_files = try me.base.sess.src_files.allCurrentlyTrackedSrcFiles(&mem_temp.allocator);
        for (src_files) |src_file| {
            if (me.base.shouldAbort())
                return;
            const lock = src_file.mutex.acquire();
            defer lock.release();
            const direct_imports = (src_file.intel orelse continue).direct_imports orelse continue;
            for (direct_imports) |src_file_path| {
                if (me.base.shouldAbort())
                    return;
                if (src_file_path.len != 0) {
                    var list = importers.getValue(src_file_path) orelse add: {
                        const new_list = try mem_temp.allocator.create(std.StringHashMap(void));
                        new_list.* = std.StringHashMap(void).init(&mem_temp.allocator);
                        _ = try importers.put(src_file_path, new_list);
                        break :add new_list;
                    };
                    _ = try list.put(src_file.full_path, {});
                }
            }
        }

        var iter = importers.iterator();
        while (iter.next()) |entry| {
            if (me.base.shouldAbort())
                return;

            if (me.base.sess.src_files.getByFullPath(entry.key)) |src_file| {
                const lock = src_file.mutex.acquire();
                defer lock.release();
                src_file.direct_importers.clear();
                var iter_sub = entry.value.iterator();
                while (iter_sub.next()) |importer|
                    _ = try src_file.direct_importers.put(importer.key, {});
            }
        }
    }
};

pub const WorkerBuildRuns = struct {
    base: Base = Base{},
    diag_src_file_ids_to_clear_next_time: ?std.AutoHashMap(u64, void) = null,
    const Base = Worker(WorkerBuildRuns, u64, false, 8, 123, 123);

    fn deinit(me: *WorkerBuildRuns) void {
        if (me.diag_src_file_ids_to_clear_next_time) |src_file_ids|
            src_file_ids.deinit();
    }

    fn workPendingJobs(me: *WorkerBuildRuns, mem_temp: *std.heap.ArenaAllocator, jobs_queue: []const u64) !void {
        if (me.diag_src_file_ids_to_clear_next_time == null)
            me.diag_src_file_ids_to_clear_next_time = std.AutoHashMap(u64, void).init(me.base.sess.mem_alloc);

        var build_dir_paths = std.StringHashMap(void).init(&mem_temp.allocator);
        for (try me.base.sess.src_files.getByIds(&mem_temp.allocator, jobs_queue)) |maybe_src_file|
            if (maybe_src_file) |src_file| for (try src_file.affectedBuildDirs(mem_temp)) |build_dir_path| {
                _ = try build_dir_paths.put(build_dir_path, {});
            };
        if (build_dir_paths.count() == 0)
            return;
        if (SrcFiles.onBuildRuns) |onBuildRuns|
            onBuildRuns(.{ .begun = {} });
        defer if (SrcFiles.onBuildRuns) |onBuildRuns|
            onBuildRuns(.{ .ended = {} });

        var diag_src_file_ids_potential = try std.ArrayList(u64).initCapacity(&mem_temp.allocator, 8 * build_dir_paths.count());
        for (try me.base.sess.src_files.allCurrentlyTrackedSrcFiles(&mem_temp.allocator)) |src_file| {
            const lock = src_file.mutex.acquire();
            defer lock.release();
            if (me.base.shouldAbort())
                return;
            if (build_dir_paths.contains(src_file.build_zig_dir_path)) {
                _ = try diag_src_file_ids_potential.append(src_file.id);
                src_file.clearBuildIssues();
            } else if (me.diag_src_file_ids_to_clear_next_time.?.contains(src_file.id))
                src_file.clearBuildIssues();
        }
        try me.base.sess.workers.issues_announcer.base.appendJobs(try zag.mem.hashMapKeys(u64, &mem_temp.allocator, me.diag_src_file_ids_to_clear_next_time.?));
        me.diag_src_file_ids_to_clear_next_time.?.clear();
        try me.base.sess.workers.issues_announcer.base.appendJobs(diag_src_file_ids_potential.toSliceConst());
        var diag_src_file_ids_actual = try std.ArrayList(u64).initCapacity(&mem_temp.allocator, diag_src_file_ids_potential.len);

        var iter = build_dir_paths.iterator();
        while (iter.next()) |entry| {
            if (me.base.shouldAbort())
                return;
            const build_dir_path = entry.key;
            if (SrcFiles.onBuildRuns) |onBuildRuns|
                onBuildRuns(.{ .cur_build_dir = build_dir_path });
            const start_time = std.time.milliTimestamp();
            std.debug.warn("zig build:\t{}...\n", .{build_dir_path});
            if (std.ChildProcess.exec(&mem_temp.allocator, &[_]Str{ me.base.sess.zig_install.exePath(), "build" }, build_dir_path, null, std.math.maxInt(usize))) |outcome| {
                std.debug.warn("\t...took {d:3.3}s.\n", .{@intToFloat(f64, std.time.milliTimestamp() - start_time) / @as(f64, 1000.0)});
                if (outcome.stderr.len != 0) {
                    var most_recent_err: ?*SrcFile.Note = null;
                    var most_recent_err_src_file_id: u64 = undefined;
                    var any_file_issues_created = false;
                    const needle_err = ": error:";
                    const needle_note = ": note: ";
                    var iter_lines = std.mem.tokenize(outcome.stderr, "\r\n");
                    while (iter_lines.next()) |line| {
                        const idx_err = std.mem.indexOf(u8, line, needle_err);
                        var is_note = (idx_err == null);
                        const idx = idx_err orelse std.mem.indexOf(u8, line, needle_note) orelse continue;
                        const msg = std.mem.trim(u8, line[idx + 8 .. line.len], " \t");
                        const path_and_pos = line[0..idx];
                        const idx_colon_last = std.mem.lastIndexOfScalar(u8, path_and_pos, ':') orelse continue;
                        const idx_colon_first = std.mem.lastIndexOfScalar(u8, path_and_pos[0..idx_colon_last], ':') orelse continue;
                        const full_file_path = if (std.fs.path.resolve(&mem_temp.allocator, &[_]Str{ build_dir_path, path_and_pos[0..idx_colon_first] })) |resolved_path|
                            resolved_path
                        else |err| {
                            std.debug.warn("{} when trying to path-join: '{s}' ++ '{s}'\n", .{ err, build_dir_path, path_and_pos[0..idx_colon_first] });
                            continue;
                        };
                        if (std.mem.endsWith(u8, full_file_path, ".zig"))
                            try me.base.sess.src_files.ensureFilesTracked(mem_temp, &[_]SrcFiles.EnsureTracked{
                                .{ .absolute_path = full_file_path },
                            });
                        const pos_line = std.fmt.parseInt(usize, path_and_pos[idx_colon_first + 1 .. idx_colon_last], 10) catch continue;
                        const pos_char = std.fmt.parseInt(usize, path_and_pos[idx_colon_last + 1 ..], 10) catch continue;

                        if (!is_note) {
                            const build_issue = SrcFile.Note{
                                .message = try std.mem.dupe(me.base.sess.mem_alloc, u8, msg),
                                .pos1based_line_and_char = [2]usize{ pos_line, pos_char },
                            };
                            var src_file = me.base.sess.src_files.getByFullPath(full_file_path) orelse continue;
                            const lock = src_file.mutex.acquire();
                            defer lock.release();
                            if (zag.mem.indexOf(src_file.notes.errs.build.items[0..src_file.notes.errs.build.
                                len], build_issue, 0, SrcFile.Note.equivalentIfIgnoringRelatedNotes)) |idx_err_issue|
                            {
                                most_recent_err = &src_file.notes.errs.build.items[idx_err_issue];
                                most_recent_err_src_file_id = src_file.id;
                            } else {
                                any_file_issues_created = true;
                                try diag_src_file_ids_actual.append(src_file.id);
                                const idx_err_issue = src_file.notes.errs.build.len;
                                try src_file.notes.errs.build.append(build_issue);
                                most_recent_err = &src_file.notes.errs.build.items[idx_err_issue];
                                most_recent_err_src_file_id = src_file.id;
                            }
                        } else if (most_recent_err) |err_issue| {
                            const issue_note = SrcFile.Note.Related{
                                .message = try std.mem.dupe(me.base.sess.mem_alloc, u8, msg),
                                .pos1based_line_and_char = [2]usize{ pos_line, pos_char },
                                .full_file_path = try std.mem.dupe(me.base.sess.mem_alloc, u8, full_file_path),
                            };
                            var src_file = me.base.sess.src_files.getById(most_recent_err_src_file_id) orelse continue;
                            const lock = src_file.mutex.acquire();
                            defer lock.release();
                            if (err_issue.related_notes == null)
                                err_issue.related_notes = std.ArrayList(SrcFile.Note.Related).init(me.base.sess.mem_alloc);
                            if (null == zag.mem.indexOf(err_issue.related_notes.?.items[0..err_issue.related_notes.?.len], issue_note, 0, null))
                                try err_issue.related_notes.?.append(issue_note);
                        }
                    }

                    if (!any_file_issues_created)
                        std.debug.warn("zig build {s}:\n{}\n", .{ build_dir_path, outcome.stderr });
                    break;
                }
            } else |err| switch (err) {
                error.OutOfMemory => return err,
                else => std.debug.warn("{}: zig build {s}\n", .{ err, build_dir_path }),
            }
        }
        for (diag_src_file_ids_actual.toSliceConst()) |src_file_id| {
            if (null == std.mem.indexOfScalar(u64, diag_src_file_ids_potential.toSliceConst(), src_file_id))
                _ = try me.diag_src_file_ids_to_clear_next_time.?.put(src_file_id, {});
        }
        try me.base.sess.workers.issues_announcer.base.appendJobs(diag_src_file_ids_actual.toSliceConst());
    }
};
