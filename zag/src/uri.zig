const std = @import("std");
usingnamespace @import("../zag.zig");

pub const Uri = struct {
    scheme: ?Str = null,
    authority: Str,
    path: ?Str = null,
    query: ?Str = null,
    fragment: ?Str = null,

    pub fn init(uri: Str) Uri {
        var it = Uri{ .authority = uri };
        if (std.mem.indexOfScalar(u8, it.authority, '#')) |idx| {
            it.fragment = it.authority[idx + 1 ..];
            it.authority = it.authority[0..idx];
        }
        if (std.mem.indexOfScalar(u8, it.authority, '?')) |idx| {
            it.query = it.authority[idx + 1 ..];
            it.authority = it.authority[0..idx];
        }
        if (std.mem.indexOf(u8, it.authority, "://")) |idx| {
            it.scheme = it.authority[0..idx];
            it.authority = it.authority[idx + 3 ..];
        }
        if (std.mem.indexOfScalar(u8, it.authority, '/')) |idx| {
            it.path = it.authority[idx..];
            it.authority = it.authority[0..idx];
        }
        return it;
    }
};
