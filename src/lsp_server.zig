const std = @import("std");
const zag = @import("../../zag/api.zig");

usingnamespace @import("../../jsonic/api.zig");
usingnamespace @import("./lsp_api_messages.zig");
usingnamespace @import("./lsp_api_types.zig");
usingnamespace @import("./lsp_common.zig");

pub var setup = InitializeResult{
    .capabilities = .{},
    .serverInfo = .{
        .name = "unnamed",
    },
};
pub var onOutput: fn ([]const u8) anyerror!void = undefined;

const LspApi = JsonRpc.Api(api_server_side, JsonOptions);

pub var jsonrpc = LspApi{
    .mem_alloc_for_arenas = std.heap.page_allocator,
    .onOutgoing = onOutputPrependHeader,
    .panic_instead_of_overwriting_existing_subscriber = true,
};

fn onOutputPrependHeader(owner: *std.mem.Allocator, raw_json_bytes_to_output: []const u8) void {
    callOnOutputHandlerWithHeaderPrependedOrCrash(onOutput, owner, raw_json_bytes_to_output);
}

pub fn forever(in_stream: var) !void {
    var mem_forever = std.heap.ArenaAllocator.init(jsonrpc.mem_alloc_for_arenas);
    defer mem_forever.deinit();

    jsonrpc.onRequest(.initialize, on_initialize);
    jsonrpc.onNotify(.__cancelRequest, on_cancel);
    jsonrpc.onNotify(.exit, on_exit);

    var in_stream_splitter = zag.io.HttpishHeaderBodySplittingReader(@TypeOf(in_stream)){
        .in_stream = in_stream,
        .perma_buf = &(try std.ArrayList(u8).initCapacity(&mem_forever.allocator, 256 * 1024)),
    };

    while (try in_stream_splitter.next()) |headers_and_body| {
        // const msg_headers = headers_and_body[0]; // so far no need for them
        const msg_body = headers_and_body[1];
        jsonrpc.incoming(msg_body) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => std.debug.warn("\nbad JSON input message triggered '{s}' error:\n{s}\n", .{ @errorName(err), msg_body }),
        };
    }
}

fn on_initialize(in: JsonRpc.Arg(InitializeParams)) JsonRpc.Ret(InitializeResult) {
    std.debug.warn("\n\nINIT\n{}\n\n{}\n\n", .{ in.it, setup });
    return .{ .ok = setup };
}

fn on_cancel(in: JsonRpc.Arg(CancelParams)) void {
    // TODO
}

fn on_exit(in: JsonRpc.Arg(void)) void {
    std.os.exit(0);
}
