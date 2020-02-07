const std = @import("std");
const zag = @import("../../zag/api.zig");
const jsonic = @import("../../jsonic/api.zig");

usingnamespace @import("./lsp_api_messages.zig");
usingnamespace @import("./lsp_api_types.zig");
usingnamespace @import("./lsp_common.zig");

const LspApi = jsonic.Rpc.Api(Server, api_server_side, JsonOptions);

pub const Server = struct {
    pub const Ctx = LspApi.Ctx;

    precis: InitializeResult = InitializeResult{
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

    __mem_forever: std.heap.ArenaAllocator = undefined,

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
            name_for_own_req_ids = me.precis.serverInfo.?.name;
        me.__mem_forever = std.heap.ArenaAllocator.init(me.api.mem_alloc_for_arenas);
        defer {
            me.__mem_forever.deinit();
            me.__mem_forever = undefined;
            me.initialized = null;
        }

        me.api.onRequest(.initialize, on_initialize);
        me.api.onNotify(.__cancelRequest, on_cancel);
        me.api.onNotify(.exit, on_exit);

        var in_stream_splitter = zag.io.HttpishHeaderBodySplittingReader(@TypeOf(in_stream)){
            .in_stream = in_stream,
            .perma_buf = &(try std.ArrayList(u8).initCapacity(&me.__mem_forever.allocator, 256 * 1024)),
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

    fn onOutputPrependHeader(me: *Server, owner: *std.mem.Allocator, raw_json_bytes_to_output: []const u8) void {
        std.debug.warn("\n\n>>>>>>>>>>>>>{}<<<<<<<<<<\n\n", .{raw_json_bytes_to_output});
        callOnOutputHandlerWithHeaderPrependedOrCrash(me.onOutput, owner, raw_json_bytes_to_output);
    }
};

fn on_initialize(ctx: LspApi.Ctx(InitializeParams)) !jsonic.Rpc.Result(InitializeResult) {
    const me: *Server = ctx.inst;
    me.initialized = try zag.mem.fullDeepCopyTo(&me.__mem_forever, ctx.value);
    return jsonic.Rpc.Result(InitializeResult){ .ok = me.precis };
}

fn on_cancel(ctx: LspApi.Ctx(CancelParams)) error{}!void {
    // no-op until we go multi-threaded, if ever
}

fn on_exit(ctx: LspApi.Ctx(void)) error{}!void {
    std.os.exit(0);
}
