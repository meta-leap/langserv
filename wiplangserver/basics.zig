usingnamespace @import("./_usingnamespace.zig");

pub var zsess = Session{};
pub var mem_alloc = if (std.builtin.mode == .Debug) &mem_alloc_debug.allocator else std.heap.allocator;
pub var mem_alloc_debug = zag.debug.Allocator.init(std.heap.page_allocator);

// could later prepend timestamps etc.
pub inline fn logToStderr(comptime fmt: Str, args: var) void {
    std.debug.warn(fmt, args);
}
