const std = @import("std");

pub const Str = []const u8;

pub const of = zag.mem.of;
pub const make = zag.mem.make;

pub const zag = struct {
    pub const debug = @import("./src/debug.zig");
    pub const fs = @import("./src/fs.zig");
    pub const Flatree = @import("./src/flatree.zig").Flatree;
    pub const io = @import("./src/io.zig");
    pub const mem = @import("./src/mem.zig");
    pub const meta = @import("./src/meta.zig");
    pub const util = @import("./src/util.zig");

    pub fn Locked(comptime T: type) type {
        return struct {
            lock: std.Mutex.Held,
            item: T,

            pub fn deinitAndUnlock(me: *Locked(T)) void {
                me.lock.release();
                if (@hasDecl(switch (@typeInfo(T)) {
                    else => T,
                    .Pointer => |ptr_info| ptr_info.child,
                }, "deinit"))
                    me.item.deinit();
            }
        };
    }

    pub fn Range(comptime T: type) type {
        return struct {
            start: T,
            end: T,

            pub fn length(me: *const @This()) T {
                return me.end - me.start;
            }
        };
    }
};
