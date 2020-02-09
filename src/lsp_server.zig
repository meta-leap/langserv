const std = @import("std");
const zag = @import("../../zag/zag.zig");
const jsonic = @import("../../jsonic/jsonic.zig");
usingnamespace @import("./lsp_api_messages.zig");
usingnamespace @import("./lsp_api_types.zig");
usingnamespace @import("./lsp_common.zig");

const LspApi = jsonic.Rpc.Api(Server, api_server_side, JsonOptions);

pub const Server = struct {
    pub const Ctx = LspApi.Ctx;

    cfg: InitializeResult = InitializeResult{
        .capabilities = ServerCapabilities{},
        .serverInfo = .{ .name = "unnamed" },
    },
    initialized: ?InitializeParams = null,
    onOutput: fn ([]const u8) anyerror!void,
    api: LspApi = LspApi{
        .owner = undefined,
        .mem_alloc_for_arenas = std.heap.page_allocator,
        .onOutgoing = onOutputPrependHeader,
    },

    mem_forever: ?std.heap.ArenaAllocator = null,

    pub fn forever(me: *Server, in_stream: var) !void {
        me.api.owner = me;
        me.initialized = null;

        if (me.api.__.handlers_requests[@enumToInt(api_server_side.RequestIn.initialize)]) |_|
            return error.CallerAlreadySubscribedToLspServerReservedInitializeMsg;
        if (me.api.__.handlers_notifies[@enumToInt(api_server_side.NotifyIn.__cancelRequest)]) |_|
            return error.CallerAlreadySubscribedToLspServerReservedCancelRequestMsg;
        if (me.api.__.handlers_notifies[@enumToInt(api_server_side.NotifyIn.exit)]) |_|
            return error.CallerAlreadySubscribedToLspServerReservedExitMsg;

        if (name_for_own_req_ids.len == 0)
            name_for_own_req_ids = me.cfg.serverInfo.?.name;
        me.mem_forever = std.heap.ArenaAllocator.init(me.api.mem_alloc_for_arenas);
        defer {
            me.mem_forever.?.deinit();
            me.mem_forever = null;
            me.initialized = null;
        }

        me.api.onRequest(.initialize, on_initialize);
        me.api.onNotify(.__cancelRequest, on_cancel);
        me.api.onNotify(.exit, on_exit);

        var in_stream_splitter = zag.io.HttpishHeaderBodySplittingReader(@TypeOf(in_stream)){
            .in_stream = in_stream,
            .perma_buf = &(try std.ArrayList(u8).initCapacity(&me.mem_forever.?.allocator, 128 * 1024)),
        };

        while (try in_stream_splitter.next()) |headers_and_body| {
            // const msg_headers = headers_and_body[0]; // so far no need for them
            const msg_body = headers_and_body[1];
            me.api.incoming(msg_body) catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => std.debug.warn(
                    "\nbad JSON input message triggered '{s}' error:\n{s}\n",
                    .{ @errorName(err), msg_body },
                ),
            };
        }
    }

    fn onOutputPrependHeader(mem: *std.mem.Allocator, me: *Server, raw_json_bytes_to_output: []const u8) void {
        // std.debug.warn("\n\n>>>>>>>>>>>>>{}<<<<<<<<<<\n\n", .{raw_json_bytes_to_output});
        callOnOutputHandlerWithHeaderPrependedOrCrash(mem, me.onOutput, raw_json_bytes_to_output);
    }
};

fn on_initialize(ctx: LspApi.Ctx(InitializeParams)) !jsonic.Rpc.Result(InitializeResult) {
    const me: *Server = ctx.inst;
    me.initialized = try zag.mem.fullDeepCopyTo(&me.mem_forever.?, ctx.value);
    return jsonic.Rpc.Result(InitializeResult){ .ok = me.cfg };
}

fn on_cancel(ctx: LspApi.Ctx(CancelParams)) error{}!void {
    // no-op until we go multi-threaded, if ever
}

fn on_exit(ctx: LspApi.Ctx(void)) error{}!void {
    std.os.exit(0);
}
