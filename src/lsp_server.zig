const std = @import("std");
const zag = @import("../../zag/api.zig");

usingnamespace @import("../../jsonic/api.zig");
usingnamespace @import("./lsp_api_messages.zig");
usingnamespace @import("./lsp_api_types.zig");

pub var name: []const u8 = "unnamed";

pub var onOutput: fn ([]const u8) anyerror!void = undefined;

const LspApi = JsonRpc.Api(api_server_side, @import("./lsp_json_settings.zig").Default);

pub var lsp_api = LspApi{
    .mem_alloc_for_arenas = std.heap.page_allocator,
    .onOutgoing = onOutputPrependHeader,
};

fn onOutputPrependHeader(raw_json_bytes: []const u8) void {
    const full_out_bytes = std.fmt.
        allocPrint(lsp_api.mem_alloc_for_arenas, "Content-Length: {d}\r\n\r\n{s}", .{ raw_json_bytes.len, raw_json_bytes }) catch
        |err| @panic(@errorName(err));
    defer lsp_api.mem_alloc_for_arenas.free(full_out_bytes);
    onOutput(full_out_bytes) catch
        |err| @panic(@errorName(err));
}

pub fn serveForever(in_stream: var) !void {
    var mem_forever = std.heap.ArenaAllocator.init(lsp_api.mem_alloc_for_arenas);
    defer mem_forever.deinit();

    lsp_api.onRequest(.initialize, on_initialize);

    var in_stream_splitter = zag.io.HttpishHeaderBodySplittingReader(@TypeOf(in_stream)){
        .in_stream = in_stream,
        .perma_buf = &(try std.ArrayList(u8).initCapacity(&mem_forever.allocator, 256 * 1024)),
    };

    while (try in_stream_splitter.next()) |headers_and_body| {
        // const msg_headers = headers_and_body[0]; // so far no need for them
        const msg_body = headers_and_body[1];
        lsp_api.incoming(msg_body) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => std.debug.warn("\nbad JSON input message triggered '{s}' error:\n{s}\n", .{ @errorName(err), msg_body }),
        };
    }
}

fn on_initialize(in: JsonRpc.Arg(InitializeParams)) JsonRpc.Ret(InitializeResult) {
    return .{ .ok = undefined };
}
