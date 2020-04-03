const std = @import("std");
usingnamespace @import("../../zag/zag.zig");

const AnyValue = @import("./json_anyvalue.zig").AnyValue;

pub const Util = struct {
    pub const During = enum {
        marshaling,
        unmarshaling,
    };

    nesting_depth_fallback: comptime_int = 32,
    nesting_depth_default_add: comptime_int = 5,
    unmarshal_set_optionals_null_on_bad_inputs: bool = false,
    unmarshal_err_on_missing_nonvoid_nonoptional_fields: bool = true,
    marshal_omit_optional_struct_fields_if_null: bool = true,

    pub fn marshal(comptime me: *const Util, mem: *std.mem.Allocator, from: var) std.mem.Allocator.Error!std.json.Value {
        const T = comptime @TypeOf(from);
        const type_info = comptime @typeInfo(T);

        if (T == std.json.Value)
            return from;
        if (T == *std.json.Value or T == *const std.json.Value)
            return from.*;
        if (T == AnyValue or T == *AnyValue or T == *const AnyValue)
            return try from.toStd(mem);
        if (T == Str or T == []u8)
            return std.json.Value{ .String = from };
        if (type_info == .Bool)
            return std.json.Value{ .Bool = from };
        if (type_info == .Int or type_info == .ComptimeInt)
            return std.json.Value{ .Integer = @intCast(i64, from) };
        if (type_info == .Float or type_info == .ComptimeFloat)
            return std.json.Value{ .Float = from };
        if (type_info == .Null or type_info == .Void)
            return std.json.Value{ .Null = .{} };
        if (type_info == .Enum)
            return std.json.Value{ .Integer = @enumToInt(from) };
        if (type_info == .Optional)
            return if (from) |it| try me.marshal(mem, it) else .{ .Null = .{} };
        if (type_info == .Pointer) {
            if (type_info.Pointer.size != .Slice)
                return try me.marshal(mem, from.*)
            else {
                var ret = try mem.alloc(std.json.Value, from.len);
                for (from) |_, i|
                    ret[i] = try me.marshal(mem, from[i]);
                return std.json.Value{ .Array = .{ .len = ret.len, .items = ret, .allocator = mem } };
            }
        }
        if (type_info == .Union) {
            comptime var i = comptime zag.meta.memberCount(T);
            inline while (i > 0) {
                i -= 1;
                if (@enumToInt(std.meta.activeTag(from)) == i) {
                    return try me.marshal(mem, @field(from, comptime zag.meta.zag.meta.memberName(T, i)));
                }
            }
            unreachable;
        }
        if (type_info == .Struct) {
            const is_hashmap = comptime zag.meta.isTypeHashMapLikeDuckwise(T);

            var ret = std.json.Value{ .Object = std.json.ObjectMap.init(mem) };
            try ret.Object.ensureCapacity(if (is_hashmap) from.count() else comptime zag.meta.memberCount(T));

            if (is_hashmap) {
                var iter = from.iterator();
                while (iter.next()) |pair|
                    _ = try ret.Object.put(pair.key, try me.marshal(mem, pair.value));
            } else {
                comptime var is_jsonrpc_response = false;
                inline for (type_info.Struct.decls) |*decl|
                    if (comptime std.mem.eql(u8, decl.name, "__is_jsonrpc_response")) {
                        is_jsonrpc_response = true;
                        break;
                    };
                comptime var i = comptime zag.meta.memberCount(T);
                inline while (i > 0) {
                    i -= 1;
                    comptime const TField = comptime zag.meta.memberType(T, i);
                    comptime const field_type_info = comptime @typeInfo(TField);
                    const field_name = comptime zag.meta.memberName(T, i);
                    const field_value = @field(from, field_name);
                    if (comptime (field_type_info == .Struct and
                        std.mem.eql(u8, field_name, @typeName(TField))))
                    {
                        var obj = (try me.marshal(mem, field_value)).Object.iterator();
                        while (obj.next()) |pair|
                            _ = try ret.Object.put(pair.key, pair.value);
                    } else {
                        const is_omittable = comptime (field_type_info == .Optional and me.marshal_omit_optional_struct_fields_if_null);
                        var should = is_jsonrpc_response or (!is_omittable) or (field_value != null);
                        if (should) // TODO! check "control flow attempts to use compile-time variable at runtime" if above `var` is either `const` or its value expression directly inside this `if`-cond
                            _ = try ret.Object.put(field_name, try me.marshal(mem, field_value));
                    }
                }
            }
            return ret;
        }
        @compileError("please file an issue to support JSON-marshaling of: " ++ @typeName(T));
    }

    pub fn unmarshal(comptime me: *const Util, comptime T: type, mem: *std.mem.Allocator, from: *const std.json.Value) error{
        MissingField,
        UnexpectedInputValueFormat,
        OutOfMemory,
    }!T {
        const type_info = comptime @typeInfo(T);
        if (T == *const std.json.Value)
            return from;
        if (T == std.json.Value)
            return from.*;
        if (T == AnyValue)
            return try AnyValue.fromStd(mem, from);
        if (T == Str or T == []u8)
            return switch (from.*) {
                .String => |jstr| jstr,
                .Bool => |jbool| if (jbool) "true" else "false",
                .Integer => |jint| try std.fmt.allocPrint(mem, "{}", .{jint}),
                .Float => |jfloat| try std.fmt.allocPrint(mem, "{}", .{jfloat}),
                .Null => "",
                else => error.UnexpectedInputValueFormat,
            };
        if (T == bool)
            return switch (from.*) {
                .Bool => |jbool| jbool,
                .Null => false,
                .String => |jstr| if (std.mem.eql(u8, "true", jstr)) true else (if (std.mem.eql(u8, "false", jstr)) false else error.UnexpectedInputValueFormat),
                .Integer => |jint| if (jint == 1) true else (if (jint == 0) false else error.UnexpectedInputValueFormat),
                else => error.UnexpectedInputValueFormat,
            };
        if (type_info == .Int)
            return switch (from.*) {
                .Integer => |jint| @intCast(T, jint),
                .Float => |jfloat| if (jfloat < @intToFloat(f64, std.math.minInt(T)) or jfloat > @intToFloat(f64, std.math.maxInt(T)))
                    error.UnexpectedInputValueFormat
                else
                    @intCast(T, @floatToInt(T, jfloat)),
                .String => |jstr| if (std.fmt.parseInt(T, jstr, 10)) |ok| @intCast(T, ok) else |_| error.UnexpectedInputValueFormat,
                .Null => @intCast(T, 0),
                else => error.UnexpectedInputValueFormat,
            };
        if (type_info == .Float)
            return switch (from.*) {
                .Float => |jfloat| @floatCast(T, jfloat),
                .Integer => |jint| @floatCast(T, @intToFloat(T, jint)),
                .String => |jstr| if (std.fmt.parseFloat(T, jstr)) |ok| @floatCast(T, ok) else |_| error.UnexpectedInputValueFormat,
                .Null => @floatCast(T, 0.0),
                else => error.UnexpectedInputValueFormat,
            };
        if (type_info == .Enum) {
            const TEnum = std.meta.TagType(T);
            return switch (from.*) {
                .Integer => |jint| std.meta.intToEnum(T, jint) catch error.UnexpectedInputValueFormat,
                .String => |jstr| std.meta.stringToEnum(T, jstr) orelse (if (std.fmt.parseInt(TEnum, jstr, 10)) |i| (std.meta.intToEnum(T, i) catch error.UnexpectedInputValueFormat) else |_| error.UnexpectedInputValueFormat),
                .Float => |jfloat| if (jfloat < @intToFloat(f64, std.math.minInt(TEnum)) or jfloat > @intToFloat(f64, std.math.maxInt(TEnum)))
                    error.UnexpectedInputValueFormat
                else
                    std.meta.intToEnum(T, @floatToInt(TEnum, jfloat)) catch error.UnexpectedInputValueFormat,
                else => error.UnexpectedInputValueFormat,
            };
        }
        if (type_info == .Void)
            return switch (from.*) {
                .Null => {},
                else => error.UnexpectedInputValueFormat,
            };
        if (type_info == .Optional) switch (from.*) {
            .Null => return null,
            else => if (me.unmarshal(type_info.Optional.child, mem, from)) |ok|
                return ok
            else |err| if (err == error.UnexpectedInputValueFormat and comptime me.unmarshal_set_optionals_null_on_bad_inputs)
                return null
            else
                return err,
        };
        if (type_info == .Pointer) {
            if (type_info.Pointer.size != .Slice) {
                var ret = try mem.create(type_info.Pointer.child);
                ret.* = try me.unmarshal(type_info.Pointer.child, mem, from);
                return ret;
            }
            switch (from.*) {
                .Array => |jarr| {
                    var ret = try mem.alloc(type_info.Pointer.child, jarr.len);
                    for (jarr.items[0..jarr.len]) |*jval, i|
                        ret[i] = try me.unmarshal(type_info.Pointer.child, mem, jval);
                    return ret;
                },
                else => return error.UnexpectedInputValueFormat,
            }
        }
        if (type_info == .Struct) {
            switch (from.*) {
                .Object => |*jmap| {
                    if (comptime zag.meta.isTypeHashMapLikeDuckwise(T)) {
                        var ret = T.init(mem);
                        try ret.ensureCapacity(jmap.count());
                        var iter = jmap.iterator();
                        while (iter.next()) |pair|
                            _ = try ret.put(pair.key, pair.value);
                        return ret;
                    }

                    var ret = zag.mem.zeroed(T);
                    comptime var i = comptime zag.meta.memberCount(T);
                    inline while (i > 0) {
                        i -= 1;
                        const field_name = comptime zag.meta.memberName(T, i);
                        const TField = comptime zag.meta.memberType(T, i);
                        const field_embed = comptime (@typeInfo(TField) == .Struct and std.mem.eql(u8, field_name, @typeName(TField)));
                        if (field_embed)
                            @field(ret, field_name) = try me.unmarshal(TField, mem, from)
                        else if (jmap.getValue(field_name)) |*jval|
                            @field(ret, field_name) = try me.unmarshal(TField, mem, jval)
                        else if (me.unmarshal_err_on_missing_nonvoid_nonoptional_fields) {
                            // return error.MissingField; // TODO! Zig currently segfaults here, check back later
                        }
                    }
                    return ret;
                },
                else => return error.UnexpectedInputValueFormat,
            }
        }
        @compileError("please file an issue to support JSON-unmarshaling into: " ++ @typeName(T));
    }

    /// json.Value equality comparison: for `.Array`s and `.Object`s, equal
    /// sizes are prerequisite before further probing into their contents.
    pub fn eql(comptime me: *const Util, one: std.json.Value, two: std.json.Value) bool {
        if (std.meta.activeTag(one) == std.meta.activeTag(two)) switch (one) {
            .Null => return true,
            .Bool => |one_bool| return one_bool == two.Bool,
            .Integer => |one_int| return one_int == two.Integer,
            .Float => |one_float| return one_float == two.Float,
            .String => |one_string| return std.mem.eql(u8, one_string, two.String),

            .Array => |one_array| if (one_array.len == two.Array.len) {
                for (one_array.items[0..one_array.len]) |one_array_item, i|
                    if (!me.eql(one_array_item, two.Array.items[i]))
                        return false;
                return true;
            },

            .Object => |one_object| if (one_object.count() == two.Object.count()) {
                var hash_map_iter = one_object.iterator();
                while (hash_map_iter.next()) |item| {
                    if (two.Object.getValue(item.key)) |two_value| {
                        if (!me.eql(item.value, two_value)) return false;
                    } else return false;
                }
                return true;
            },
        };
        return false;
    }

    pub fn nestingDepth(comptime me: *const Util, comptime add_maybe: ?comptime_int, comptime T: type) comptime_int {
        comptime {
            const type_info = @typeInfo(T);
            const add = add_maybe orelse me.nesting_depth_default_add;
            if (T == std.json.Value or T == *std.json.Value or T == *const std.json.Value or
                T == AnyValue or T == *AnyValue or T == *const AnyValue)
                return add + me.nesting_depth_fallback;
            if (type_info == .Optional)
                return add + me.nestingDepth(0, type_info.Optional.child);
            if (type_info == .Pointer)
                return add + (if (type_info.Pointer.size == .One) 0 else 1) + me.nestingDepth(0, type_info.Pointer.child);
            if (type_info == .Union) {
                var max = 0;
                inline for (type_info.Union.fields) |*field|
                    max = std.math.max(max, me.nestingDepth(0, field.field_type));
                return add + max;
            }
            if (type_info == .Struct) {
                var max = 0;
                if (comptime zag.meta.isTypeHashMapLikeDuckwise(T)) {
                    Key = @typeInfo(T.KV).Struct.fields[std.meta.fieldIndex(T.KV, "key")].field_type;
                    Value = @typeInfo(T.KV).Struct.fields[std.meta.fieldIndex(T.KV, "value")].field_type;
                    max = std.math.max(me.nestingDepth(0, Key), me.nestingDepth(0, Value));
                } else inline for (type_info.Struct.fields) |*field|
                    max = std.math.max(max, me.nestingDepth(0, field.field_type));
                return add + 1 + max;
            }
            return add;
        }
    }

    pub fn toBytes(out_buf: *std.ArrayList(u8), json_value: *const std.json.Value, comptime nesting_depth: comptime_int) !void {
        while (true) {
            var stream_out_into_buf = std.io.SliceOutStream.init(out_buf.items);
            if (json_value.dumpStream(&stream_out_into_buf.stream, nesting_depth)) {
                if (stream_out_into_buf.pos == out_buf.capacity())
                    try out_buf.ensureCapacity(8 + ((out_buf.capacity() * 3) / 2))
                else {
                    out_buf.len = stream_out_into_buf.pos;
                    return;
                }
            } else |err| switch (err) { // "OutOfMemory" here means "out of fixed-buf space"
                error.OutOfMemory => try out_buf.ensureCapacity(8 + ((out_buf.capacity() * 3) / 2)),
            }
        }
    }
};
