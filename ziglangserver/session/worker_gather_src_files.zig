const std = @import("std");
const zag = @import("../../../zag/zag.zig");
usingnamespace @import("./session.zig");

pub const WorkerThatGathersSrcFiles = struct {
    session: *Session = undefined,
    thread: *std.Thread = undefined,

    time_last_enqueued: std.atomic.Int(u64) = std.atomic.Int(u64).init(0),
    jobs_queue: std.ArrayList(JobEntry) = undefined,
    mutex: std.Mutex = std.Mutex.init(),

    pub const JobEntry = union(enum) {
        dir_added: []const u8,
        dir_removed: []const u8,
        file_created: []const u8,
        file_modified: []const u8,
        file_deleted: []const u8,
    };

    pub fn forever(me: *WorkerThatGathersSrcFiles) u8 {
        me.jobs_queue = std.ArrayList(JobEntry).init(me.session.mem_alloc);
        defer me.jobs_queue.deinit();

        repeat: while (true) {
            if (me.session.deinited) break :repeat;

            var time_last_enqueued = me.time_last_enqueued.get();
            if (time_last_enqueued == 0 or (std.time.milliTimestamp() - time_last_enqueued) < 234) {
                std.time.sleep(42 * std.time.millisecond);
                continue;
            } else
                me.fetchAndWorkPendingJobs() catch return 1;
        }
        return 0;
    }

    fn fetchAndWorkPendingJobs(me: *WorkerThatGathersSrcFiles) !void {
        me.time_last_enqueued.set(0);

        var jobs_queue: []JobEntry = &[_]JobEntry{};
        {
            const lock = me.mutex.acquire();
            defer lock.release();
            jobs_queue = try std.mem.dupe(me.session.mem_alloc, JobEntry, me.jobs_queue.items[0..me.jobs_queue.len]);
            me.jobs_queue.len = 0;
        }
        defer zag.mem.fullDeepFreeFrom(me.session.mem_alloc, jobs_queue);

        for (jobs_queue) |job| {
            if (me.session.deinited) return;

            switch (job) {
                .dir_added => |dir_path| {
                    var src_file_paths = std.ArrayList([]const u8).init(me.session.mem_alloc);
                    defer src_file_paths.deinit();
                    try zag.io.gatherAllFiles(&src_file_paths, dir_path, "", ".zig");
                    for (src_file_paths.items[0..src_file_paths.len]) |src_file_path|
                        std.debug.warn("{}\n", .{src_file_path});
                },
                .dir_removed => {},
                .file_created => {},
                .file_modified => {},
                .file_deleted => {},
            }
        }
    }

    pub fn enqueueJobs(me: *WorkerThatGathersSrcFiles, job_entries: []const JobEntry) !void {
        const lock = me.mutex.acquire();
        defer lock.release();
        try me.jobs_queue.appendSlice(try zag.mem.fullDeepCopyTo(me.session.mem_alloc, job_entries));
        me.time_last_enqueued.set(std.time.milliTimestamp());
    }
};
