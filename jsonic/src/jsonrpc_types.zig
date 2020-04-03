const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
usingnamespace @import("./json_util.zig");
usingnamespace @import("./json_anyvalue.zig");

pub const StandardErrorCodes = enum(isize) {
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
    serverErrorStart = -32099,
    serverErrorEnd = -32000,
    ServerNotInitialized = -32002,
    UnknownErrorCode = -32001,
};

pub const ResponseError = struct {
    /// see `StandardErrorCodes` enumeration
    code: isize,
    message: Str,
    data: ?AnyValue = null,
};

pub const Spec = struct {
    newReqId: fn (*std.mem.Allocator) anyerror!std.json.Value,
    RequestIn: type,
    RequestOut: type,
    NotifyIn: type,
    NotifyOut: type,

    pub fn inverse(me: Spec, newReqId: ?fn (*std.mem.Allocator) anyerror!std.json.Value) Spec {
        return Spec{
            .newReqId = newReqId orelse me.newReqId,
            .RequestIn = me.RequestOut,
            .RequestOut = me.RequestIn,
            .NotifyIn = me.NotifyOut,
            .NotifyOut = me.NotifyIn,
        };
    }
};

pub fn Result(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ResponseError,

        fn toJsonRpcResponse(me: @This(), id: var) union(enum) {
            with_result: struct {
                id: @TypeOf(id),
                result: T,
                jsonrpc: Str = "2.0",

                const __is_jsonrpc_response: void = {};
            },
            with_error: struct {
                id: @TypeOf(id),
                @"error": ResponseError,
                jsonrpc: Str = "2.0",

                const __is_jsonrpc_response: void = {};
            },
        } {
            return switch (me) {
                .ok => |ok| .{ .with_result = .{ .id = id, .result = ok } },
                .err => |err| .{ .with_error = .{ .id = id, .@"error" = err } },
            };
        }
    };
}

pub const MsgKind = enum {
    notification,
    request,
    response,
};

pub const Options = struct {
    json: Util = Util{}, // TODO: type coercion of anon struct literal to struct
};
