const std = @import("std");
const zag = @import("../../../zag/zag.zig");

pub const Session = struct {
    alloc_for_arenas: *std.mem.Allocator = undefined,
    tmp_dir_parent_dir: ?std.fs.Dir = null,
    tmp_dir: ?std.fs.Dir = null,
    zig_std_lib_dir_path: ?[]const u8 = null,

    pub fn init(me: *Session, alloc_for_arenas: *std.mem.Allocator, tmp_dir_parent_dir_path: []const u8) !void {
        me.alloc_for_arenas = alloc_for_arenas;
        //   /lib/zig/std/std.zig

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
                var cmd_ziginitlib = try std.ChildProcess.init(&[_][]const u8{ "zig", "init-lib" }, alloc_for_arenas);
                defer cmd_ziginitlib.deinit();
                switch (cmd_ziginitlib.spawnAndWait() catch break :zig_std_lib_dir_path) {
                    else => {},
                    .Exited => {
                        var cmd_zigbuildtest = try std.ChildProcess.init(&[_][]const u8{ "zig", "build", "test", "--cache-dir", "__" }, alloc_for_arenas);
                        defer cmd_zigbuildtest.deinit();
                        switch (cmd_zigbuildtest.spawnAndWait() catch break :zig_std_lib_dir_path) {
                            else => {},
                            .Exited => {
                                const windowstrulyblows = try std.fs.path.join(alloc_for_arenas, &[_][]const u8{ "__", "h" });
                                defer alloc_for_arenas.free(windowstrulyblows);
                                var cache_dir = tmp_dir.openDirList(windowstrulyblows) catch break :zig_std_lib_dir_path;
                                defer cache_dir.close();
                                std.debug.warn("\n\n\nNOIIIIIIIIIIIIIIIIIICE\n\n\n", .{});
                            },
                        }
                    },
                }
            }
        }
    }

    pub fn deinit(me: *Session) void {
        if (me.tmp_dir != null)
            me.tmp_dir.?.close();
        if (me.tmp_dir_parent_dir != null) {
            // me.tmp_dir_parent_dir.?.deleteTree("ziglsp") catch {};
            me.tmp_dir_parent_dir.?.close();
        }
    }
};
