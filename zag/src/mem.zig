const std = @import("std");
const zag = @import("../zag.zig").zag;

pub inline fn deepValueEquality(one: var, two: var) bool {
    const T = @TypeOf(one);
    comptime if (T != @TypeOf(two))
        return false;
    switch (@typeInfo(T)) {
        else => return (one == two),
        .Optional => return (one == null and two == null) or
            (one != null and two != null and deepValueEquality(one.?, two.?)),
        .Struct => |struct_info| {
            inline for (struct_info.fields) |*field|
                if (!deepValueEquality(@field(one, field.name), @field(two, field.name)))
                    return false;
            return true;
        },
        .Union => |union_info| if (std.meta.activeTag(one) == std.meta.activeTag(two)) {
            inline for (union_info.fields) |*field|
                if (std.meta.activeTag(one) == @intToEnum(@TagType(T), field.enum_field.?.value))
                    return deepValueEquality(@field(one, field.name), @field(two, field.name));
        },
        .Array => if (one.len == two.len) {
            for (one) |_, i|
                if (!deepValueEquality(one[i], two[i]))
                    return false;
            return true;
        },
        .Pointer => |ptr_info| if (ptr_info.size != .Slice)
            return (one == two or deepValueEquality(one.*, two.*))
        else switch (@typeInfo(ptr_info.child)) {
            .Pointer, .Array, .Union, .Struct, .Optional => if (one.len == two.len) {
                if (one.ptr != two.ptr) for (one) |_, i|
                    if (!deepValueEquality(one[i], two[i]))
                        return false;
                return true;
            },
            else => return std.mem.eql(ptr_info.child, one, two),
        },
    }
    return false;
}

/// usually, an ArrayList is vastly preferable. but sometimes cumbersome for not-critical-enough sections..
pub inline fn dupeAppend(mem: *std.mem.Allocator, slice: var, item: @typeInfo(@TypeOf(slice)).Pointer.child) ![]@typeInfo(@TypeOf(slice)).Pointer.child {
    const T = @typeInfo(@TypeOf(slice)).Pointer.child;
    var ret = try mem.alloc(T, 1 + slice.len);
    if (slice.len != 0)
        std.mem.copy(T, ret[0..slice.len], slice);
    ret[slice.len] = item;
    return ret;
}

/// usually, an ArrayList is vastly preferable. but sometimes cumbersome for not-critical-enough sections..
pub inline fn dupePrepend(mem: *std.mem.Allocator, slice: var, item: @typeInfo(@TypeOf(slice)).Pointer.child) !@TypeOf(slice) {
    const T = @typeInfo(@TypeOf(slice)).Pointer.child;
    var ret = try mem.alloc(T, 1 + slice.len);
    if (slice.len != 0)
        std.mem.copy(T, ret[1..ret.len], slice);
    ret[0] = item;
    return ret;
}

pub inline fn eqlUnordered(comptime T: type, slice1: []const T, slice2: []const T) bool {
    if (slice1.len == slice2.len) {
        for (slice1) |_, i|
            if (null == indexOf(slice2, slice1[i], 0, null))
                return false;
        return true;
    }
    return false;
}

pub fn indexOf(slice: var, item: @typeInfo(@TypeOf(slice)).Pointer.child, index: usize, maybe_eql: ?fn (@typeInfo(@TypeOf(slice)).Pointer.child, @typeInfo(@TypeOf(slice)).Pointer.child) bool) ?usize {
    var i: usize = index;
    if (maybe_eql) |eql| {
        while (i < slice.len) : (i += 1) if (eql(item, slice[i]))
            return i;
    } else while (i < slice.len) : (i += 1) if (deepValueEquality(item, slice[i]))
        return i;
    return null;
}

pub inline fn indexOfLast(slice: var, item: @typeInfo(@TypeOf(slice)).Pointer.child, index: usize, maybe_eql: ?fn (@typeInfo(@TypeOf(slice)).Pointer.child, @typeInfo(@TypeOf(slice)).Pointer.child) bool) ?usize {
    var i: usize = index;
    if (i < slice.len) {
        if (maybe_eql) |eql| {
            while (i > -1) : (i -= 1) if (eql(item, slice[i]))
                return i;
        } else while (i > -1) : (i -= 1) if (deepValueEquality(item, slice[i]))
            return i;
    }
    return null;
}

pub inline fn reoccursLater(slice: var, index: usize, maybe_eql: ?fn (@typeInfo(@TypeOf(slice)).Pointer.child, @typeInfo(@TypeOf(slice)).Pointer.child) bool) ?usize {
    var i: usize = index + 1;
    if (maybe_eql) |eql| {
        while (i < slice.len) : (i += 1) if (eql(slice[index], slice[i]))
            return i;
    } else while (i < slice.len) : (i += 1) if (deepValueEquality(slice[index], slice[i]))
        return i;
    return null;
}

pub inline fn edit(buf: var, buf_len: usize, start: usize, end: usize, new: var) usize {
    const buf_cap = buf.len;
    std.debug.assert(end >= start);
    const old_len = end - start;
    const buf_len_new = (buf_len - old_len) + new.len;
    std.debug.assert(buf_cap >= buf_len_new);

    const end_new = start + new.len;
    if (old_len < new.len) {
        const diff = new.len - old_len;
        var i = buf_len_new - 1;
        while (i >= end_new) {
            buf[i] = buf[i - diff];
            i -= 1;
        }
    }
    std.mem.copy(u8, buf[start..end_new], new);
    if (old_len > new.len)
        std.mem.copy(u8, buf[end_new..buf_len_new], buf[end..buf_len]);
    return buf_len_new;
}

pub inline fn count(slice: var, needle: @typeInfo(@TypeOf(slice)).Pointer.child) usize {
    var c: usize = 0;
    for (slice) |item| {
        if (item == needle)
            c += 1;
    }
    return c;
}

pub inline fn replaceScalar(slice: var, old: @typeInfo(@TypeOf(slice)).Pointer.child, new: @typeInfo(@TypeOf(slice)).Pointer.child) void {
    for (slice) |value, i| {
        if (value == old)
            slice[i] = new;
    }
}

pub inline fn replaceScalars(slice: var, old: []const @typeInfo(@TypeOf(slice)).Pointer.child, new: @typeInfo(@TypeOf(slice)).Pointer.child) void {
    for (slice) |value, i| {
        if (std.mem.indexOfScalar(@TypeOf(new), old, value)) |_|
            slice[i] = new;
    }
}

pub inline fn replace(
    mem: *std.mem.Allocator,
    slice: var,
    old: []const @typeInfo(@TypeOf(slice)).Pointer.child,
    new: []const @typeInfo(@TypeOf(slice)).Pointer.child,
    how_often: enum { once, repeatedly },
) ![]const @typeInfo(@TypeOf(slice)).Pointer.child {
    const T = @typeInfo(@TypeOf(slice)).Pointer.child;
    var in = slice;

    var ret = try std.ArrayList(T).initCapacity(mem, in.len + in.len / 3);
    while (true) {
        var pos: usize = 0;
        if (old.len != 0 and in.len >= old.len) {
            var i: usize = 0;
            const old_last: usize = old.len - 1;
            const old_1char = (old.len == 1);
            const i_last: usize = in.len - old.len;
            while (i <= i_last) : (i += 1) {
                if (in[i] == old[0] and (old_1char or
                    (in[i + old_last] == old[old_last] and
                    std.mem.eql(u8, in[i + 1 .. i + old_last], old[1..old_last]))))
                {
                    try ret.appendSlice(in[pos..i]);
                    try ret.appendSlice(new);
                    pos = i + old.len;
                    i = pos - 1; // we'll get incr'd by the `while`
                }
            }
        }
        try ret.appendSlice(in[pos..]);
        if (how_often == .once or pos == 0) break else in = ret.toOwnedSlice();
    }
    return ret.toOwnedSlice();
}

pub inline fn replaceAny(
    mem: *std.mem.Allocator,
    slice: var,
    old_new: []const [2][]const @typeInfo(@TypeOf(slice)).Pointer.child,
) ![]const @typeInfo(@TypeOf(slice)).Pointer.child {
    const T = @typeInfo(@TypeOf(slice)).Pointer.child;

    var ret = try std.ArrayList(T).initCapacity(mem, slice.len + slice.len / 3);
    var pos: usize = 0;
    if (old_new.len != 0) {
        var i: usize = 0;
        while (i < slice.len) : (i += 1) {
            for (old_new) |_, idx| if (i <= slice.len - old_new[idx][0].len and
                old_new[idx][0].len != 0 and slice.len >= old_new[idx][0].len)
            {
                const old_last: usize = old_new[idx][0].len - 1;
                if (slice[i] == old_new[idx][0][0] and (old_new[idx][0].len == 1 or
                    (slice[i + old_last] == old_new[idx][0][old_last] and
                    std.mem.eql(u8, slice[i + 1 .. i + old_last], old_new[idx][0][1..old_last]))))
                {
                    try ret.appendSlice(slice[pos..i]);
                    try ret.appendSlice(old_new[idx][1]);
                    pos = i + old_new[idx][0].len;
                    i = pos - 1; // we'll get incr'd by the `while`
                    break;
                }
            };
        }
    }
    try ret.appendSlice(slice[pos..]);
    return ret.toOwnedSlice();
}

pub inline fn trimPrefix(comptime T: type, slice: []const T, prefix: []const T) []const T {
    return if (!std.mem.startsWith(T, slice, prefix)) slice else slice[prefix.len..slice.len];
}

pub fn hashMapKeys(comptime TKey: type, mem: *std.mem.Allocator, hash_map: var) ![]TKey {
    var ret = try mem.alloc(TKey, hash_map.count());
    var iter = hash_map.iterator();
    var i: usize = 0;
    while (iter.next()) |entry| : (i += 1)
        ret[i] = entry.key;
    return ret;
}

pub fn fullDeepFreeFrom(mem: *std.mem.Allocator, it: var) void {
    const T = @TypeOf(it);
    switch (@typeInfo(T)) {
        .Optional => if (it) |non_null| {
            fullDeepFreeFrom(mem, non_null);
        },
        .Struct => |struct_info| if (zag.meta.WhatArrayList(T) != noreturn) {
            std.debug.assert(it.allocator == mem);
            it.deinit();
        } else inline for (struct_info.fields) |*field| {
            fullDeepFreeFrom(mem, @field(it, field.name));
        },
        .Union => |union_info| inline for (union_info.fields) |*field| {
            if (std.meta.activeTag(it) == @intToEnum(@TagType(T), field.enum_field.?.value)) {
                fullDeepFreeFrom(mem, @field(it, field.name));
                break;
            }
        },
        .Array => for (it) |_, i| {
            fullDeepFreeFrom(mem, it[i]);
        },
        .Pointer => |ptr_info| if (ptr_info.size != .Slice) {
            if (comptime (@sizeOf(ptr_info.child) != 0)) {
                fullDeepFreeFrom(mem, it.*);
                mem.destroy(it);
            }
        } else {
            if (it.len > 0) {
                for (it) |_, i| {
                    fullDeepFreeFrom(mem, it[i]);
                }
                mem.free(it);
            }
        },
        else => {},
    }
}

pub fn fullDeepCopyTo(mem: *std.mem.Allocator, it: var) std.mem.Allocator.Error!@TypeOf(it) {
    const T = @TypeOf(it);
    var ret: T = undefined;
    switch (@typeInfo(T)) {
        .Optional => ret = if (it == null) null else try fullDeepCopyTo(mem, it.?),
        .Struct => |struct_info| {
            const TElem = zag.meta.WhatArrayList(T);
            if (TElem != noreturn) {
                ret.len = it.len;
                ret.allocator = mem;
                ret.items = try fullDeepCopyTo(mem, it.items[0..it.len]);
            } else inline for (struct_info.fields) |*field|
                @field(ret, field.name) = try fullDeepCopyTo(mem, @field(it, field.name));
        },
        .Union => |union_info| inline for (union_info.fields) |*field|
            if (std.meta.activeTag(it) == @intToEnum(@TagType(T), field.enum_field.?.value)) {
                ret = @unionInit(T, field.name, try fullDeepCopyTo(mem, @field(it, field.name)));
                break;
            },
        .Array => for (it) |_, i| {
            ret[i] = try fullDeepCopyTo(mem, it[i]);
        },
        .Pointer => |ptr_info| if (ptr_info.size != .Slice) {
            ret = try mem.create(ptr_info.child);
            ret.* = try fullDeepCopyTo(mem, it.*);
        } else {
            var slice: []ptr_info.child = try mem.alloc(ptr_info.child, it.len);
            for (it) |_, i| {
                slice[i] = try fullDeepCopyTo(mem, it[i]);
            }
            ret = slice;
        },
        else => ret = it,
    }
    return ret;
}

pub inline fn times(mem: *std.mem.Allocator, how_many_repetitions: usize, repeat_what: var) ![]@typeInfo(@TypeOf(repeat_what)).Pointer.child {
    const T = @typeInfo(@TypeOf(repeat_what)).Pointer.child;
    var ret = try mem.alloc(T, how_many_repetitions * repeat_what.len);
    var i: usize = 0;
    while (i < how_many_repetitions) : (i += 1)
        std.mem.copy(T, ret[i * repeat_what.len ..], repeat_what);
    return ret;
}

pub inline fn zeroed(comptime T: type) T {
    var ret: T = undefined;
    switch (comptime @typeInfo(T)) {
        .Bool => ret = false,
        .Int, .ComptimeInt => ret = @intCast(T, 0),
        .Float, .ComptimeFloat => ret = @floatCast(T, 0.0),
        .Optional => ret = null,
        .Enum => @ptrCast(*@TagType(T), &ret).* = 0,
        .Array => |array_info| for (ret) |_, i| {
            ret[i] = zeroed(array_info.child);
        },
        .Pointer => |ptr_info| {
            if (ptr_info.size == .Slice)
                ret = &[_]ptr_info.child{}
            else
                ret.* = zeroed(ptr_info.child);
        },
        .Struct => |struct_info| inline for (struct_info.fields) |*field| {
            @field(ret, field.name) = zeroed(field.field_type);
        },
        .Union => |union_info| inline for (union_info.fields) |*field| {
            ret = @unionInit(T, field.name, zeroed(field.field_type));
            break;
        },
        else => ret = T{},
    }
    return ret;
}

pub fn inOrderPermutations(comptime T: type, mem: *std.mem.Allocator, items: []const []const T) ![]const T {
    var ret: []T = &[_]T{};

    var num_results: usize = 1;
    for (items) |item|
        num_results *= item.len;

    if (num_results != 0) {
        ret = try mem.alloc(T, num_results * items.len);

        var idxs = try mem.alloc(usize, items.len);
        defer mem.free(idxs);
        for (idxs) |_, i|
            idxs[i] = 0;
        var i_ret: usize = 0;
        var i: usize = 0;
        while (i < items.len) {
            // fetch next "item"
            i = 0;
            while (i < items.len) : (i += 1)
                ret[i_ret + i] = items[i][idxs[i]];
            i_ret += items.len;

            // advance the multiple-indices-of-only-runtime-known-scale cursor `idxs`
            i = 0;
            while (i < items.len) : (i += 1) {
                idxs[i] += 1;
                if (idxs[i] < items[i].len)
                    break;
                idxs[i] = 0;
            }
        }
    }
    return ret;
}

pub inline fn make(mem: *std.mem.Allocator, comptime T: type, items: var) ![]T {
    return std.mem.dupe(mem, T, of(T, items));
}

pub inline fn enHeap(mem: *std.mem.Allocator, item: var) !*@TypeOf(item) {
    var ptr = try mem.create(@TypeOf(item));
    ptr.* = item;
    return ptr;
}

/// TODO: totally bugged without inline! revisit around zig 1.0, dont remove inline til then.
pub inline fn of(comptime T: type, items: var) []T {
    const TTup = @TypeOf(items);
    const num_items = @typeInfo(TTup).Struct.fields.len;
    var arr: [num_items]T = undefined;
    inline for (@typeInfo(TTup).Struct.fields) |*field, i| {
        var item = @field(items, field.name);
        const TItem = @TypeOf(item);
        if (TItem == T)
            arr[i] = item
        else if (@typeInfo(TItem) == .Struct and @typeInfo(TItem).Struct.fields.len != 0 and @typeInfo(TItem).Struct.fields[0].name.len == 1 and @typeInfo(TItem).Struct.fields[0].name[0] == '0') {
            var sub = of(@typeInfo(T).Array.child, item);
            comptime var idx: usize = 0;
            inline while (idx < @typeInfo(T).Array.len) : (idx += 1)
                arr[i][idx] = sub[idx];
        } else
            arr[i] = @as(T, item);
    }
    return arr[0..];
}
