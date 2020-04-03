const std = @import("std");
usingnamespace @import("../zag.zig");

pub fn WhatArrayList(comptime TList: type) type {
    comptime var Len: type = noreturn;
    comptime var Alloc: type = noreturn;
    comptime var Items: type = noreturn;
    inline for (@typeInfo(TList).Struct.fields) |*field| {
        if (std.mem.eql(u8, field.name, "len"))
            Len = field.field_type
        else if (std.mem.eql(u8, field.name, "allocator"))
            Alloc = field.field_type
        else if (std.mem.eql(u8, field.name, "items"))
            Items = field.field_type
        else
            return noreturn;
    }
    if (Len == usize and Alloc == *std.mem.Allocator) switch (@typeInfo(Items)) {
        .Pointer => |ptr_info| if (ptr_info.size == .Slice)
            return ptr_info.child,
        else => {},
    };
    return noreturn;
}

pub fn memberCount(comptime T: type) usize {
    return comptime std.meta.fields(T).len;
}

pub fn memberName(comptime T: type, comptime index: usize) Str {
    return comptime std.meta.fields(T)[index].name;
}

pub fn memberType(comptime T: type, comptime index: usize) type {
    return comptime std.meta.fields(T)[index].field_type;
}

pub fn isTypeHashMapLikeDuckwise(comptime T: type) bool {
    switch (@typeInfo(T)) {
        else => {},
        .Struct => |*maybe_hashmap_struct_info| inline for (maybe_hashmap_struct_info.decls) |*decl_in_hashmap|
            comptime if (decl_in_hashmap.is_pub and std.mem.eql(u8, "iterator", decl_in_hashmap.name)) switch (decl_in_hashmap.data) {
                else => {},
                .Fn => |*fn_decl_hashmap_iterator| switch (@typeInfo(fn_decl_hashmap_iterator.return_type)) {
                    else => {},
                    .Struct => |*maybe_iterator_struct_info| inline for (maybe_iterator_struct_info.decls) |*decl_in_iterator|
                        comptime if (decl_in_iterator.is_pub and std.mem.eql(u8, "next", decl_in_iterator.name)) switch (decl_in_iterator.data) {
                            else => {},
                            .Fn => |*fn_decl_iterator_next| switch (@typeInfo(fn_decl_iterator_next.return_type)) {
                                else => {},
                                .Optional => |*iter_ret_opt| switch (@typeInfo(iter_ret_opt.child)) {
                                    else => {},
                                    .Pointer => |*iter_ret_opt_ptr| switch (@typeInfo(iter_ret_opt_ptr.child)) {
                                        else => {},
                                        .Struct => |*kv_struct| if (2 == kv_struct.fields.len and
                                            std.mem.eql(u8, "key", kv_struct.fields[0].name) and
                                            std.mem.eql(u8, "value", kv_struct.fields[1].name))
                                        inline for (maybe_hashmap_struct_info.decls) |*decl2_in_hashmap|
                                            comptime if (decl2_in_hashmap.is_pub and std.mem.eql(u8, "put", decl2_in_hashmap.name)) switch (decl2_in_hashmap.data) {
                                                else => {},
                                                .Fn => |*fn_decl_hashmap_put| switch (@typeInfo(fn_decl_hashmap_put.fn_type)) {
                                                    else => {},
                                                    .Fn => |*fn_decl_hashmap_put_type| if (fn_decl_hashmap_put_type.args.len == 3)
                                                        if (fn_decl_hashmap_put_type.return_type) |PutRet|
                                                            if (fn_decl_hashmap_put_type.args[0].arg_type) |PutArgSelf|
                                                                if (fn_decl_hashmap_put_type.args[1].arg_type) |PutArgKey|
                                                                    if (fn_decl_hashmap_put_type.args[2].arg_type) |PutArgValue|
                                                                        if (@typeInfo(PutArgSelf) == .Pointer and
                                                                            @typeInfo(PutArgSelf).Pointer.child == T and
                                                                            PutArgKey == kv_struct.fields[0].field_type and
                                                                            PutArgValue == kv_struct.fields[1].field_type and
                                                                            @typeInfo(PutRet) == .ErrorUnion and
                                                                            @typeInfo(@typeInfo(PutRet).ErrorUnion.payload) == .Optional)
                                                                            return true,
                                                },
                                            },
                                    },
                                },
                            },
                        },
                },
            },
    }
    return false;
}
