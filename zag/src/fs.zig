const std = @import("std");
usingnamespace @import("../zag.zig");

pub fn gatherAllFilesInto(dest_list: *std.ArrayList(Str), dir_path: Str, fileNameOkToGather: fn (Str) bool, subDirNameOkToWalkInto: ?fn (Str) bool) !usize {
    return gatherAllFiles(Str, "", dest_list, dir_path, fileNameOkToGather, subDirNameOkToWalkInto);
}

pub fn gatherAllFiles(
    comptime T: type,
    comptime field_name: Str,
    dest_list: *std.ArrayList(T),
    dir_path: Str,
    fileNameOkToGather: fn (Str) bool,
    subDirNameOkToWalkInto: ?fn (Str) bool,
) !usize {
    var num_files_gathered: usize = 0;
    var dirs_to_walk = try std.ArrayList(Str).initCapacity(dest_list.allocator, 128);
    defer dirs_to_walk.deinit();
    try dirs_to_walk.append(try std.mem.dupe(dest_list.allocator, u8, dir_path));

    while (dirs_to_walk.popOrNull()) |cur_dir_path| {
        defer dest_list.allocator.free(cur_dir_path);
        var dir = std.fs.cwd().openDirList(cur_dir_path) catch continue;
        defer dir.close();
        var iter = dir.iterate();
        while (true) {
            if (iter.next() catch continue) |entry| {
                if (entry.kind == .Directory) {
                    if (subDirNameOkToWalkInto == null or subDirNameOkToWalkInto.?(entry.name)) {
                        const full_path = try std.fs.path.join(dest_list.allocator, &[_]Str{ cur_dir_path, entry.name });
                        try dirs_to_walk.append(full_path);
                    }
                } else if ((entry.kind == .File or entry.kind == .SymLink) and fileNameOkToGather(entry.name)) {
                    const full_path = try std.fs.path.join(dest_list.allocator, &[_]Str{ cur_dir_path, entry.name });
                    if (T == Str)
                        try dest_list.append(full_path)
                    else {
                        var item: T = .{};
                        @field(item, field_name) = full_path;
                        try dest_list.append(item);
                    }
                    num_files_gathered += 1;
                }
            } else
                break;
        }
    }
    return num_files_gathered;
}

pub const TmpDir = struct {
    shared_or_sys_tmp_root_dir: std.fs.Dir = undefined,
    inner_parent_dir_name: Str = undefined,
    cur_dir: std.fs.Dir = undefined,

    pub fn init(
        mem: *std.mem.Allocator,
        shared_or_sys_tmp_root_dir_path: Str,
        comptime inner_parent_dir_name: Str,
        cur_tmp_dir_name_prefix: Str,
        chdir_into: bool,
    ) !?TmpDir {
        var me: TmpDir = undefined;
        var close_dir_on_later_failure = false;

        if (std.fs.cwd().openDirTraverse(shared_or_sys_tmp_root_dir_path)) |dir| attempt: {
            close_dir_on_later_failure = true;
            me.shared_or_sys_tmp_root_dir = dir;
            const uniqueish_id = try @import("./util.zig").uniqueishId(mem, cur_tmp_dir_name_prefix);
            defer mem.free(uniqueish_id);
            const cur_tmp_dir_path = try std.fs.path.join(mem, &[_]Str{
                shared_or_sys_tmp_root_dir_path,
                inner_parent_dir_name,
                uniqueish_id,
            });
            defer mem.free(cur_tmp_dir_path);
            std.fs.cwd().makePath(cur_tmp_dir_path) catch break :attempt;
            if (chdir_into)
                std.os.chdir(cur_tmp_dir_path) catch break :attempt;
            me.cur_dir = std.fs.cwd().openDirTraverse(cur_tmp_dir_path) catch break :attempt;
            me.inner_parent_dir_name = inner_parent_dir_name;

            return me;
        } else |_| {}

        if (close_dir_on_later_failure)
            me.shared_or_sys_tmp_root_dir.close();
        return null;
    }

    pub fn deinit(me: *TmpDir, try_del_tree: bool) void {
        me.cur_dir.close();
        if (try_del_tree)
            me.shared_or_sys_tmp_root_dir.deleteTree(me.inner_parent_dir_name) catch {};
        me.shared_or_sys_tmp_root_dir.close();
    }
};
