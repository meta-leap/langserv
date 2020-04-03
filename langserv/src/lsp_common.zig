const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
const jsonic = @import("../../jsonic/jsonic.zig");

pub fn callOnOutputHandlerWithHeaderPrependedOrCrash(
    mem: *std.mem.Allocator,
    onOutput: fn (Str) anyerror!void,
    raw_json_bytes_to_output: Str,
) void {
    const full_out_bytes = std.fmt.allocPrint(
        mem,
        "Content-Length: {d}\r\n\r\n{s}",
        .{ raw_json_bytes_to_output.len, raw_json_bytes_to_output },
    ) catch
        |err| @panic(@errorName(err));
    onOutput(full_out_bytes) catch
        |err| @panic(@errorName(err));
}

pub const jsonrpc_options = jsonic.Rpc.Options{
    .json = .{
        .unmarshal_set_optionals_null_on_bad_inputs = true,
        .unmarshal_err_on_missing_nonvoid_nonoptional_fields = false,
    },
};

fn isStructFieldEmbedded(comptime TStruct: type, comptime field_name: Str, comptime TField: type, comptime when: jsonic.Jsonic.During) bool {
    return std.mem.eql(u8, field_name, @typeName(TField));
}

pub var name_for_own_req_ids: Str = "";

pub fn nextReqId(mem: *std.mem.Allocator) !std.json.Value {
    const global_counter = struct {
        var req_id: isize = 0;
    };
    global_counter.req_id += 1;

    const str = try std.fmt.allocPrint(mem, "lsp_{s}_req_{d}", .{ name_for_own_req_ids, global_counter.req_id });
    return std.json.Value{ .String = str };
}
