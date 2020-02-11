const std = @import("std");
const zag = @import("../../../zag/zag.zig");

pub const Session = struct {
    alloc_for_arenas: *std.mem.Allocator = undefined,
    tmp_dir: ?zag.io.TmpDir = null,
    zig_std_lib_dir_path: ?[]const u8 = null,

    pub fn init(me: *Session, alloc_for_arenas: *std.mem.Allocator, shared_or_sys_tmp_root_dir_path: []const u8) !void {
        me.alloc_for_arenas = alloc_for_arenas;
        var mem = std.heap.ArenaAllocator.init(alloc_for_arenas);
        defer mem.deinit();

        me.tmp_dir = try zag.io.TmpDir.init(&mem, shared_or_sys_tmp_root_dir_path, "ziglsp", "sess", true);

        if (me.tmp_dir != null) {
            me.zig_std_lib_dir_path = try @import("./zig_inst_info.zig").
                digForStdLibDirPathInNewlyCreatedTempProj(&mem, &me.tmp_dir.?, "zig", "__");
            me.tmp_dir.?.cur_dir.deleteTree("__") catch {};
            std.debug.warn("\n\n\n\n{}\n\n\n\n", .{me.zig_std_lib_dir_path});
        }
    }

    pub fn deinit(me: *Session) void {
        if (me.tmp_dir != null)
            me.tmp_dir.?.deinit(true);
    }
};
