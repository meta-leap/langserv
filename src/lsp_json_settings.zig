const std = @import("std");

usingnamespace @import("../../jsonic/api.zig");

pub const Default = JsonRpc.Options{
    .rewriteUnionFieldNameToJsonRpcMethodName = rewriteUnionFieldNameToJsonRpcMethodName,
    .rewriteJsonRpcMethodNameToUnionFieldName = rewriteJsonRpcMethodNameToUnionFieldName,
    .json = Jsonic{
        .rewriteStructFieldNameToJsonObjectKey = rewriteStructFieldNameToJsonObjectKey,
        .isStructFieldEmbedded = isStructFieldEmbedded,
        .unmarshal_set_optionals_null_on_bad_inputs = true,
        .unmarshal_err_on_missing_nonvoid_nonoptional_fields = false,
    },
};

fn rewriteUnionFieldNameToJsonRpcMethodName(comptime union_type: type, comptime union_field_idx: comptime_int, comptime union_field_name: []const u8) []const u8 {
    return union_field_name;
}

fn rewriteJsonRpcMethodNameToUnionFieldName(incoming_kind: JsonRpc.MsgKind, jsonrpc_method_name: []const u8) []const u8 {
    return jsonrpc_method_name;
}

fn rewriteStructFieldNameToJsonObjectKey(comptime TStruct: type, field_name: []const u8, when: Jsonic.During) []const u8 {
    return field_name;
}

fn isStructFieldEmbedded(comptime TStruct: type, field_name: []const u8, comptime TField: type, comptime when: Jsonic.During) bool {
    return false;
}
