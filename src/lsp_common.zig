const std = @import("std");
const zag = @import("../../zag/api.zig");
const jsonic = @import("../../jsonic/api.zig");

pub fn callOnOutputHandlerWithHeaderPrependedOrCrash(
    onOutput: fn ([]const u8) anyerror!void,
    owner: *std.mem.Allocator,
    raw_json_bytes_to_output: []const u8,
) void {
    const full_out_bytes = std.fmt.allocPrint(
        owner,
        "Content-Length: {d}\r\n\r\n{s}",
        .{ raw_json_bytes_to_output.len, raw_json_bytes_to_output },
    ) catch
        |err| @panic(@errorName(err));
    onOutput(full_out_bytes) catch
        |err| @panic(@errorName(err));
}

pub const JsonOptions = jsonic.Rpc.Options{
    .rewriteUnionFieldNameToJsonRpcMethodName = rewriteUnionFieldNameToJsonRpcMethodName,
    .rewriteJsonRpcMethodNameToUnionFieldName = rewriteJsonRpcMethodNameToUnionFieldName,
    .json = .{
        .rewriteStructFieldNameToJsonObjectKey = rewriteStructFieldNameToJsonObjectKey,
        .isStructFieldEmbedded = isStructFieldEmbedded,
        .unmarshal_set_optionals_null_on_bad_inputs = true,
        .unmarshal_err_on_missing_nonvoid_nonoptional_fields = false,
    },
};

fn rewriteUnionFieldNameToJsonRpcMethodName(comptime union_type: type, comptime union_field_idx: comptime_int, comptime union_field_name: []const u8, owner: *std.mem.Allocator) ![]const u8 {
    var name: []u8 = try std.mem.dupe(owner, u8, union_field_name);
    zag.mem.replaceScalar(u8, name, '_', '/');
    if (name[0] == '/')
        name[0] = '$';
    return name;
}

fn rewriteJsonRpcMethodNameToUnionFieldName(incoming_kind: jsonic.Rpc.MsgKind, jsonrpc_method_name: []const u8, owner: *std.mem.Allocator) ![]const u8 {
    var name = try std.mem.dupe(owner, u8, jsonrpc_method_name);
    zag.mem.replaceScalars(u8, name, "$/", '_');
    return name;
}

fn rewriteStructFieldNameToJsonObjectKey(comptime TStruct: type, comptime field_name: []const u8, comptime when: jsonic.Jsonic.During) []const u8 {
    return if (!std.mem.endsWith(u8, field_name, "__"))
        field_name
    else
        field_name[0 .. field_name.len - 2];
}

fn isStructFieldEmbedded(comptime TStruct: type, comptime field_name: []const u8, comptime TField: type, comptime when: jsonic.Jsonic.During) bool {
    return std.mem.eql(u8, field_name, @typeName(TField));
}

pub var name_for_own_req_ids: []const u8 = "";

pub fn nextReqId(owner: *std.mem.Allocator) !std.json.Value {
    const global_counter = struct {
        var req_id: isize = 0;
    };
    global_counter.req_id += 1;

    const str = try std.fmt.allocPrint(owner, "lsp_{s}_req_{d}", .{ name_for_own_req_ids, global_counter.req_id });
    return std.json.Value{ .String = str };
}