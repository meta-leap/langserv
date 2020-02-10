const std = @import("std");
const zag = @import("../../../zag/zag.zig");

pub const Session = struct {
    alloc_for_arenas: *std.mem.Allocator = undefined,
    tmp_dir_parent_dir: ?std.fs.Dir = null,
    tmp_dir: ?std.fs.Dir = null,
    env_buf_map: std.BufMap = undefined,
    zig_std_lib_dir_path: ?[]const u8 = null,

    pub fn init(me: *Session, alloc_for_arenas: *std.mem.Allocator, tmp_dir_parent_dir_path: []const u8) !void {
        me.alloc_for_arenas = alloc_for_arenas;
        //   /lib/zig/std/std.zig

        env_buf_map: {
            me.env_buf_map = std.BufMap.init(alloc_for_arenas);
            var i: usize = 0;
            while (i < std.os.environ.len) : (i += 1) {
                const env_var_pair_str = std.mem.toSlice(u8, std.os.environ[i]);
                if (std.mem.indexOfScalar(u8, env_var_pair_str, '=')) |idx|
                    try me.env_buf_map.set(env_var_pair_str[0..idx], env_var_pair_str[idx + 1 ..]);
            }
        }

        tmp_dir: {
            if (std.fs.cwd().openDirTraverse(tmp_dir_parent_dir_path)) |dir| {
                me.tmp_dir_parent_dir = dir;
                const tmp_dir_path = try std.fs.path.join(alloc_for_arenas, &[_][]const u8{
                    tmp_dir_parent_dir_path,
                    "ziglsp",
                    try zag.util.uniqueishId(alloc_for_arenas, "sess"),
                });
                defer alloc_for_arenas.free(tmp_dir_path);
                std.fs.makePath(alloc_for_arenas, tmp_dir_path) catch break :tmp_dir;
                std.os.chdir(tmp_dir_path) catch break :tmp_dir;
                me.tmp_dir = std.fs.cwd().openDirTraverse(tmp_dir_path) catch break :tmp_dir;
                std.debug.warn("\n\n\n{}\n", .{tmp_dir_path});
            } else |_| {}
        }

        zig_std_lib_dir_path: {
            if (me.tmp_dir) |tmp_dir| {
                std.os.execvpe(alloc_for_arenas, &[_][]const u8{ "zig", "init-lib" }, &me.env_buf_map) catch
                    break :zig_std_lib_dir_path;
            }
        }
    }

    pub fn deinit(me: *Session) void {
        me.env_buf_map.deinit();
        // if (me.tmp_dir_parent_dir) |dir|
        //     dir.deleteTree("ziglsp") catch {};
    }
};
