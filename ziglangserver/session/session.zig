const std = @import("std");
const zag = @import("../../../zag/zag.zig");
usingnamespace @import("./worker_gather_src_files.zig");

pub const Session = struct {
    mem_alloc: *std.mem.Allocator = undefined,
    tmp_dir: ?zag.io.TmpDir = null,
    deinited: bool = true,
    zig_std_lib_dir_path: ?[]const u8 = null,
    worker_gather_src_files: WorkerThatGathersSrcFiles = undefined,

    pub fn init(me: *Session, mem_alloc: *std.mem.Allocator, shared_or_sys_tmp_root_dir_path: []const u8) !void {
        std.debug.assert(me.deinited);
        me.deinited = false;
        me.mem_alloc = mem_alloc;
        var mem = std.heap.ArenaAllocator.init(mem_alloc);
        defer mem.deinit();

        me.tmp_dir = try zag.io.TmpDir.init(&mem, shared_or_sys_tmp_root_dir_path, "ziglsp", "sess", true);
        if (me.tmp_dir != null) {
            me.zig_std_lib_dir_path = try @import("./zig_inst_info.zig").
                digForStdLibDirPathInNewlyCreatedTempProj(&mem, &me.tmp_dir.?, "zig", "__");
            me.tmp_dir.?.cur_dir.deleteTree("__") catch {};
            std.debug.warn("\n\n\n\n{}\n\n\n\n", .{me.zig_std_lib_dir_path});
        }

        me.worker_gather_src_files = .{ .session = me };

        me.worker_gather_src_files.thread = try std.Thread.spawn(&me.worker_gather_src_files, WorkerThatGathersSrcFiles.forever);
    }

    pub fn deinit(me: *Session) void {
        if (!me.deinited) {
            me.deinited = true;
            if (me.tmp_dir != null)
                me.tmp_dir.?.deinit(true);
        }
    }
};
