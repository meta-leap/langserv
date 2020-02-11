const std = @import("std");
usingnamespace @import("./session.zig");

pub const WorkerThatGathersSrcFiles = struct {
    session: *Session = undefined,
    thread: *std.Thread = undefined,
    jobs_queue: std.ArrayList(JobEntry) = undefined,
    mutex: std.Mutex = std.Mutex.init(),
    most_recently_enqueued: std.atomic.Int(u64) = std.atomic.Int(u64).init(0),

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

        while (true) {
            if (me.session.deinited)
                break;

            var most_recently_enqueued = me.most_recently_enqueued.get();
            if (most_recently_enqueued == 0 or (std.time.milliTimestamp() - most_recently_enqueued) < 234) {
                std.time.sleep(42 * std.time.millisecond);
                continue;
            }
            me.most_recently_enqueued.set(0);

            var jobs_queue: []JobEntry = &[_]JobEntry{};
            const lock = me.mutex.acquire();
            if (me.jobs_queue.len > 0) {
                jobs_queue = std.mem.dupe(me.session.mem_alloc, JobEntry, me.jobs_queue.items[0..me.jobs_queue.len]) catch
                    return 1;
                me.jobs_queue.len = 0;
            }
            lock.release();

            if (jobs_queue.len > 0) {
                for (jobs_queue) |job| {
                    std.debug.warn("\n\nSth to do: {}\n\n", .{job});
                }
            }
        }
        return 0;
    }

    pub fn appendJobs(me: *WorkerThatGathersSrcFiles, job_entries: []const JobEntry) !void {
        const lock = me.mutex.acquire();
        defer lock.release();
        try me.jobs_queue.appendSlice(job_entries);
        me.most_recently_enqueued.set(std.time.milliTimestamp());
    }
};
