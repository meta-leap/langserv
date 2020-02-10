const std = @import("std");
const zag = @import("../../../zag/zag.zig");

pub const Session = struct {
    alloc_for_arenas: *std.mem.Allocator = undefined,
    tmp_dir_parent_dir: ?std.fs.Dir = null,
    tmp_dir: ?std.fs.Dir = null,
    zig_std_lib_dir_path: ?[]const u8 = null,

    pub fn init(me: *Session, alloc_for_arenas: *std.mem.Allocator, tmp_dir_parent_dir_path: []const u8) !void {
        me.alloc_for_arenas = alloc_for_arenas;

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
            } else |_| {}
        }

        if (me.tmp_dir != null) zig_std_lib_dir_path: {
            var cmd_ziginitlib = try std.ChildProcess.init(&[_][]const u8{ "zig", "init-lib" }, alloc_for_arenas);
            defer cmd_ziginitlib.deinit();
            if ((cmd_ziginitlib.spawnAndWait() catch break :zig_std_lib_dir_path) != .Exited)
                break :zig_std_lib_dir_path;

            var cmd_zigbuildtest = try std.ChildProcess.init(&[_][]const u8{ "zig", "build", "test", "--cache-dir", "__" }, alloc_for_arenas);
            defer cmd_zigbuildtest.deinit();
            if ((cmd_zigbuildtest.spawnAndWait() catch break :zig_std_lib_dir_path) != .Exited)
                break :zig_std_lib_dir_path;

            var cache_h_dir = me.tmp_dir.?.openDirList("__" ++ std.fs.path.sep_str ++ "h") catch break :zig_std_lib_dir_path;
            defer cache_h_dir.close();
            var iter = cache_h_dir.iterate();
            search: while (iter.next() catch break :zig_std_lib_dir_path) |entry| {
                if (entry.kind == .File and std.mem.endsWith(u8, entry.name, ".txt")) {
                    var txt_file = cache_h_dir.openFile(entry.name, .{}) catch break :zig_std_lib_dir_path;
                    defer txt_file.close();
                    const txt_file_bytes = try alloc_for_arenas.alloc(u8, (try txt_file.stat()).size);
                    defer alloc_for_arenas.free(txt_file_bytes);
                    _ = try txt_file.inStream().stream.readFull(txt_file_bytes);
                    var pos: usize = 0;
                    while (pos < txt_file_bytes.len) {
                        const needle = std.fs.path.sep_str ++ "lib" ++ std.fs.path.sep_str ++ "zig" ++ std.fs.path.sep_str ++ "std" ++ std.fs.path.sep_str ++ "std.zig";
                        if (std.mem.indexOfPos(u8, txt_file_bytes, pos, needle)) |idx| {
                            pos = idx + needle.len;
                            var i: usize = idx;
                            while (i > 0) : (i -= 1) if (std.fs.path.isAbsolute(txt_file_bytes[i..pos])) {
                                if (std.fs.openFileAbsolute(txt_file_bytes[i..pos], .{})) |file| {
                                    file.close();
                                    me.zig_std_lib_dir_path = std.fs.path.dirname(txt_file_bytes[i..pos]);
                                    std.debug.warn("\n\n\n{}\n\n\n", .{me.zig_std_lib_dir_path.?});
                                    break :search;
                                } else |_| {}
                            };
                        } else
                            break;
                    }
                }
            }
        }

        if (me.tmp_dir != null)
            me.tmp_dir.?.deleteTree("__") catch {};
    }

    pub fn deinit(me: *Session) void {
        if (me.tmp_dir != null)
            me.tmp_dir.?.close();
        if (me.tmp_dir_parent_dir != null) {
            me.tmp_dir_parent_dir.?.deleteTree("ziglsp") catch {};
            me.tmp_dir_parent_dir.?.close();
        }
    }
};
