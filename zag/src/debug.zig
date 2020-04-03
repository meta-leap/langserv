const std = @import("std");
usingnamespace @import("../zag.zig");

pub inline fn print(comptime fmt: Str, args: var) void {
    if (std.builtin.mode == .Debug)
        std.debug.warn(fmt, args);
}

// note: this was written before discovering the std.testing.FailingAllocator =)
// still keeping it for the report() method
pub const Allocator = struct {
    allocator: std.mem.Allocator,
    backing_allocator: *std.mem.Allocator,

    bytes_allocd: usize = 0,
    bytes_freed: usize = 0,

    pub fn init(backing_allocator: *std.mem.Allocator) Allocator {
        return .{
            .backing_allocator = backing_allocator,
            .allocator = .{
                .reallocFn = realloc,
                .shrinkFn = shrink,
            },
        };
    }

    fn realloc(allocator: *std.mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        const me = @fieldParentPtr(Allocator, "allocator", allocator);
        var ptr = try me.backing_allocator.reallocFn(me.backing_allocator, old_mem, old_align, new_size, new_align);
        if (new_size < old_mem.len)
            me.bytes_freed += old_mem.len - new_size
        else if (new_size > old_mem.len)
            me.bytes_allocd += new_size - old_mem.len;
        return ptr;
    }

    fn shrink(allocator: *std.mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        const me = @fieldParentPtr(Allocator, "allocator", allocator);
        var ptr = me.backing_allocator.shrinkFn(me.backing_allocator, old_mem, old_align, new_size, new_align);
        me.bytes_freed += old_mem.len - ptr.len;
        return ptr;
    }

    pub inline fn report(me: *Allocator, prefix: Str) void {
        const f: f64 = 1.0 / 1024.0;
        const allocd = f * @intToFloat(f64, me.bytes_allocd);
        const freed = f * @intToFloat(f64, me.bytes_freed);

        print("{s}{d:3.3}KB currently alloc'd\n\t(total allocs: {d:3.3}KB, freed: {d:3.3}KB)\n", .{ prefix, allocd - freed, allocd, freed });
    }
};
