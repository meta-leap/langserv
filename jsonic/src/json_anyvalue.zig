const std = @import("std");
usingnamespace @import("../../zag/zag.zig");

/// AnyValue can represent all JSON values, similar to std.json.Value.
/// The Jsonic un/marshalers and the JSONRPC engine support both approaches.
/// In contrast to std.json.Value, the union size is strictly 8 bytes (vs. std.json.Value
/// being approx. sizeOf(StringHashMap(std.json.Value)) for every bool/null/number,string)
/// and does not have some dangling allocator lurking inside ArrayList / HashMap fields.
/// The trade-off being that freely adding/removing items in `.array` or `.object` is not
/// on without cumbersome re-allocations and correspondingly keeping track of which
/// allocator owned memory backing the slices involved. (Non-adding/-removing in-place
/// mutations inside said slices, on the other hand, may segfault or UB if not on heap.)
pub const AnyValue = union(enum) {
    @"null": void,
    boolean: bool,
    int: i64,
    float: f64,
    string: Str,
    array: []AnyValue,
    object: []Property,

    pub const Property = struct {
        name: Str,
        value: AnyValue,
    };

    pub fn get(me: AnyValue, property_name: Str) ?AnyValue {
        for (me.object) |_, i|
            if (std.mem.eql(u8, me.object[i].name, property_name))
                return me.object[i].value;
        return null;
    }

    pub fn eql(me: AnyValue, to: AnyValue) bool {
        if (std.meta.activeTag(me) == std.meta.activeTag(to)) switch (me) {
            .@"null" => return true,
            .boolean => |b| return (b == to.boolean),
            .int => |i| return (i == to.int),
            .float => |f| return (f == to.float),
            .string => |s| return std.mem.eql(u8, s, to.string),
            .array => |arr| if (arr.len == to.array.len) {
                for (arr) |_, i|
                    if (!arr[i].eql(to.array[i]))
                        return false;
                return true;
            },
            .object => |obj| if (obj.len == to.object.len) {
                for (obj) |_, i|
                    if (!obj[i].value.eql(to.get(obj[i].name) orelse return false))
                        return false;
                return true;
            },
        };
        return false;
    }

    pub fn fromStd(mem: *std.mem.Allocator, it: *const std.json.Value) std.mem.Allocator.Error!AnyValue {
        switch (it.*) {
            .Null => return .@"null",
            .Bool => |b| return AnyValue{ .boolean = b },
            .Integer => |i| return AnyValue{ .int = i },
            .Float => |f| return AnyValue{ .float = f },
            .String => |s| return AnyValue{ .string = s },
            .Array => |*arr| {
                var ret = try mem.alloc(AnyValue, arr.len);
                var i: usize = 0;
                while (i < ret.len) : (i += 1)
                    ret[i] = try fromStd(mem, &arr.items[i]);
                return AnyValue{ .array = ret };
            },
            .Object => |*obj| {
                var ret = try mem.alloc(Property, obj.count());
                var iter = obj.iterator();
                var i: usize = 0;
                while (iter.next()) |item| {
                    ret[i].name = item.key;
                    ret[i].value = try fromStd(mem, &item.value);
                    i += 1;
                }
                return AnyValue{ .object = ret };
            },
        }
    }

    pub fn toStd(me: AnyValue, mem: *std.mem.Allocator) std.mem.Allocator.Error!std.json.Value {
        switch (me) {
            .@"null" => return std.json.Value{ .Null = {} },
            .boolean => |b| return std.json.Value{ .Bool = b },
            .int => |i| return std.json.Value{ .Integer = i },
            .float => |f| return std.json.Value{ .Float = f },
            .string => |s| return std.json.Value{ .String = s },
            .array => |arr| {
                var slice = try mem.alloc(std.json.Value, arr.len);
                for (arr) |_, i|
                    slice[i] = try arr[i].toStd(mem);
                return std.json.Value{ .Array = .{ .len = arr.len, .items = slice, .allocator = mem } };
            },
            .object => |obj| {
                var ret = std.json.ObjectMap.init(mem);
                try ret.ensureCapacity(obj.len);
                for (obj) |property|
                    _ = try ret.put(property.name, try property.value.toStd(mem));
                return std.json.Value{ .Object = ret };
            },
        }
    }
};
