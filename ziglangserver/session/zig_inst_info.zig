const std = @import("std");
usingnamespace @import("../../../zag/zag.zig");

pub fn digForStdLibDirPathInNewlyCreatedTempProj(mem: *std.heap.ArenaAllocator, tmp_dir: *zag.io.TmpDir, comptime zig_cmd_spec: Str, comptime cache_dir_name: Str) !?Str {
    const cmd_ziginitlib = std.ChildProcess.exec(&mem.allocator, &[_]Str{ zig_cmd_spec, "init-lib" }, null, null, std.math.maxInt(usize)) catch
        return null;
    if (cmd_ziginitlib.term != .Exited)
        return null;

    const cmd_zigbuildtest = std.ChildProcess.exec(&mem.allocator, &[_]Str{ zig_cmd_spec, "build", "test", "--cache-dir", cache_dir_name }, null, null, std.math.maxInt(usize)) catch
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
            const txt_file_bytes = try mem.allocator.alloc(u8, (try txt_file.stat()).size);
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
                            if (std.fs.path.dirname(txt_file_bytes[i..pos])) |dir_path|
                                return try std.mem.dupe(&mem.allocator, u8, dir_path);
                        } else |_| {}
                    };
                } else
                    break;
            }
        }
    }
    return null;
}
