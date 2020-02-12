const std = @import("std");
usingnamespace @import("../../../zag/zag.zig");
usingnamespace @import("./session.zig");

pub const SrcFilesCache = struct {
    session: *Session = undefined,
    mutex: std.Mutex = std.Mutex.init(),
};

pub const SrcFile = struct {
    //
};
