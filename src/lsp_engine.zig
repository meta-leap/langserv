const std = @import("std");
const zag = @import("zag");

usingnamespace @import("jsonic");

usingnamespace @import("./lsp_api_messages.zig");

pub var onOutput: fn ([]const u8) anyerror!void = undefined;

pub var mem_alloc_for_arenas: *std.mem.Allocator = std.heap.page_allocator;

const LspApi = JsonRpc.Api(api_spec, JsonRpc.Options{
    .rewriteUnionFieldNameToJsonRpcMethodName = rewriteUnionFieldNameToJsonRpcMethodName,
    .rewriteJsonRpcMethodNameToUnionFieldName = rewriteJsonRpcMethodNameToUnionFieldName,
    .json = Jsonic{
        .rewriteStructFieldNameToJsonObjectKey = rewriteStructFieldNameToJsonObjectKey,
        .isStructFieldEmbedded = isStructFieldEmbedded,
        .unmarshal_set_optionals_null_on_bad_inputs = true,
        .unmarshal_err_on_missing_nonvoid_nonoptional_fields = false,
    },
});

fn onOutputPrependHeader(raw_outgoing_json_bytes: []const u8) void {
    const full_out_bytes = std.fmt.
        allocPrint(mem_alloc_for_arenas, "Content-Length: {d}\r\n\r\n{s}", .{ raw_outgoing_json_bytes.len, raw_outgoing_json_bytes }) catch
        |err| @panic(@errorName(err));
    defer mem_alloc_for_arenas.free(full_out_bytes);
    onOutput(full_out_bytes) catch
        |err| @panic(@errorName(err));
}

pub fn serveForever(in_stream: var) !void {
    var mem_forever = std.heap.ArenaAllocator.init(mem_alloc_for_arenas);
    defer mem_forever.deinit();

    var jsonrpc = LspApi{
        .mem_alloc_for_arenas = mem_alloc_for_arenas,
        .onOutgoing = onOutputPrependHeader,
    };
    defer jsonrpc.deinit();

    // jsonrpc.on(init);

    var in_stream_splitter = zag.io.HttpishHeaderBodySplittingReader(@TypeOf(in_stream)){
        .in_stream = in_stream,
        .perma_buf = &(try std.ArrayList(u8).initCapacity(&mem_forever.allocator, 256 * 1024)),
    };

    while (try in_stream_splitter.next()) |headers_and_body| {
        // const msg_headers = headers_and_body[0]; // no need for them
        const msg_body = headers_and_body[1];
        jsonrpc.incoming(msg_body) catch |err| switch (err) {};
    }
}

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
