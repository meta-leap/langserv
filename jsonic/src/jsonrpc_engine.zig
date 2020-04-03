const std = @import("std");
usingnamespace @import("../../zag/zag.zig");
usingnamespace @import("./jsonrpc_types.zig");

pub fn Engine(comptime Owner: type, comptime spec: Spec, comptime options: Options) type {
    return struct {
        mem_alloc_for_arenas: *std.mem.Allocator,
        owner: *Owner,
        onOutgoing: fn (*std.mem.Allocator, *Owner, Str) void,

        __: InternalState = InternalState{
            .handlers_notifies = [_]?usize{null} ** comptime zag.meta.memberCount(spec.NotifyIn),
            .handlers_requests = [_]?usize{null} ** comptime zag.meta.memberCount(spec.RequestIn),
        },

        pub fn deinit(me: *const @This()) void {
            if (me.__.shared_out_buf) |*shared_out_buf|
                shared_out_buf.deinit();
            if (me.__.handlers_responses) |*handlers_responses| {
                var i: usize = 0;
                while (i < handlers_responses.len) : (i += 1)
                    handlers_responses.items[i].mem_arena.deinit();
                handlers_responses.deinit();
            }
        }

        pub fn onNotify(me: *@This(), comptime tag: @TagType(spec.NotifyIn), handler: fn (Ctx(comptime zag.meta.memberType(spec.NotifyIn, @enumToInt(tag)))) anyerror!void) void {
            on(spec.NotifyIn, me.__.handlers_notifies[0..], tag, handler);
        }

        pub fn onRequest(me: *@This(), comptime tag: @TagType(spec.RequestIn), handler: fn (Ctx(@typeInfo(comptime zag.meta.memberType(spec.RequestIn, @enumToInt(tag))).Fn.args[0].arg_type.?)) anyerror!Result(@typeInfo(comptime zag.meta.memberType(spec.RequestIn, @enumToInt(tag))).Fn.return_type.?)) void {
            on(spec.RequestIn, me.__.handlers_requests[0..], tag, handler);
        }

        fn on(comptime T: type, handlers: []?usize, comptime tag: @TagType(T), handler: var) void {
            const idx = comptime @enumToInt(tag);
            const fn_ptr = @ptrToInt(handler);
            handlers[idx] = fn_ptr;
        }

        pub fn notify(me: *@This(), comptime tag: @TagType(spec.NotifyOut), param: comptime zag.meta.memberType(spec.NotifyOut, @enumToInt(tag))) !void {
            return me.out(spec.NotifyOut, tag, undefined, param, null);
        }

        pub fn request(me: *@This(), comptime tag: @TagType(spec.RequestOut), req_state: var, param: @typeInfo(comptime zag.meta.memberType(spec.RequestOut, @enumToInt(tag))).Fn.args[0].arg_type.?, comptime ThenStruct: type) !void {
            return me.out(spec.RequestOut, tag, req_state, param, ThenStruct);
        }

        fn out(me: *@This(), comptime T: type, comptime tag: @TagType(T), req_state: var, param: var, comptime ThenStruct: ?type) !void {
            const is_request = (T == spec.RequestOut);
            comptime std.debug.assert(is_request or T == spec.NotifyOut);

            var mem_local = std.heap.ArenaAllocator.init(me.mem_alloc_for_arenas);
            defer mem_local.deinit();

            const idx = @enumToInt(tag);
            const method_member_name = comptime zag.meta.memberName(T, idx);

            var out_msg = std.json.Value{ .Object = std.json.ObjectMap.init(&mem_local.allocator) };
            if (@TypeOf(param) != void)
                _ = try out_msg.Object.put("params", try options.json.marshal(&mem_local.allocator, param));
            _ = try out_msg.Object.put("jsonrpc", .{ .String = "2.0" });
            _ = try out_msg.Object.put("method", .{ .String = method_member_name });

            if (is_request) {
                var mem_keep = std.heap.ArenaAllocator.init(me.mem_alloc_for_arenas);
                const req_id = try spec.newReqId(&mem_keep.allocator);
                _ = try out_msg.Object.put("id", req_id);

                if (me.__.handlers_responses == null)
                    me.__.handlers_responses = try std.ArrayList(InternalState.ResponseAwaiter).initCapacity(me.mem_alloc_for_arenas, 8);

                const fn_info_then = @typeInfo(@TypeOf(ThenStruct.?.then)).Fn;
                comptime {
                    std.debug.assert(fn_info_then.return_type != null);
                    std.debug.assert(@typeInfo(fn_info_then.return_type.?) == .ErrorUnion);
                    std.debug.assert(fn_info_then.args.len == 2);
                    std.debug.assert(fn_info_then.args[0].arg_type != null);
                    std.debug.assert(fn_info_then.args[1].arg_type != null);
                    std.debug.assert(fn_info_then.args[1].arg_type.? == Ctx(Result(@typeInfo(std.meta.fieldInfo(T, method_member_name).field_type).Fn.return_type.?)));
                }
                const ReqState = fn_info_then.args[0].arg_type orelse @TypeOf(req_state);
                if (@typeInfo(ReqState) != .Pointer and ReqState != void)
                    @compileError("your `then`s first arg must have a pointer type");
                const ReqStateVal = if (ReqState == void) void else @typeInfo(ReqState).Pointer.child;
                var state: *ReqStateVal = undefined;
                if (ReqStateVal != void) {
                    state = try mem_keep.allocator.create(ReqStateVal);
                    state.* = try zag.mem.fullDeepCopyTo(&mem_keep.allocator, if (@TypeOf(req_state) == ReqStateVal) req_state else req_state.*);
                }
                try me.__.handlers_responses.?.append(InternalState.ResponseAwaiter{
                    .mem_arena = mem_keep,
                    .req_id = req_id,
                    .req_union_idx = idx,
                    .ptr_state = if (@sizeOf(ReqStateVal) == 0) 0 else @ptrToInt(state),
                    .ptr_fn = @ptrToInt(ThenStruct.?.then),
                });
            }
            const json_out_bytes_in_shared_buf = try me.__.dumpJsonValueToSharedBuf(me.
                mem_alloc_for_arenas, &out_msg, options.json.nesting_depth_fallback);
            me.onOutgoing(&mem_local.allocator, me.owner, json_out_bytes_in_shared_buf);
        }

        pub fn incoming(me: *@This(), full_incoming_jsonrpc_msg_payload: Str) !void {
            var mem_local = std.heap.ArenaAllocator.init(me.mem_alloc_for_arenas);
            defer mem_local.deinit();

            var msg: struct {
                id: ?*std.json.Value = null,
                method: Str = undefined,
                params: ?*std.json.Value = null,
                result_ok: ?*std.json.Value = null,
                result_err: ?ResponseError = null,
                kind: MsgKind = undefined,
            } = .{};

            // FIRST: gather what we can for `msg`
            var json_parser = std.json.Parser.init(&mem_local.allocator, true);
            var json_tree = try json_parser.parse(full_incoming_jsonrpc_msg_payload);

            switch (json_tree.root) {
                else => return error.MsgIsNoJsonObj,

                std.json.Value.Object => |*hashmap| {
                    if (hashmap.getValue("id")) |*jid|
                        msg.id = jid;
                    if (hashmap.getValue("error")) |*jerror|
                        msg.result_err = try options.json.unmarshal(ResponseError, &mem_local.allocator, jerror);
                    if (hashmap.getValue("result")) |*jresult|
                        msg.result_ok = jresult;
                    if (hashmap.getValue("params")) |*jparams|
                        msg.params = jparams;

                    msg.kind = if (msg.id) |_|
                        (if (msg.result_err == null and msg.result_ok == null) MsgKind.request else MsgKind.response)
                    else
                        MsgKind.notification;

                    if (hashmap.getValue("method")) |jmethod| switch (jmethod) {
                        .String => |jstr| msg.method = jstr,
                        else => if (msg.kind != .request) return error.MsgMalformedMethodField else {
                            const json_out_bytes_in_shared_buf = try me.__.dumpJsonValueToSharedBuf(me.mem_alloc_for_arenas, &(try options.json.marshal(&mem_local.allocator, ResponseError{
                                .code = @enumToInt(StandardErrorCodes.ParseError),
                                .message = msg.method,
                            })), options.json.nesting_depth_fallback);
                            return me.onOutgoing(&mem_local.allocator, me.owner, json_out_bytes_in_shared_buf);
                        },
                    } else if (msg.kind == .request) {
                        const json_out_bytes_in_shared_buf = try me.__.dumpJsonValueToSharedBuf(me.mem_alloc_for_arenas, &(try options.json.marshal(&mem_local.allocator, ResponseError{
                            .code = @enumToInt(StandardErrorCodes.ParseError),
                            .message = @errorName(error.MsgMissingMethodField),
                        })), options.json.nesting_depth_fallback);
                        return me.onOutgoing(&mem_local.allocator, me.owner, json_out_bytes_in_shared_buf);
                    } else if (msg.kind != .response)
                        return error.MsgMissingMethodField;
                },
            }

            // NEXT: *now* handle `msg`
            switch (msg.kind) {
                .notification => {
                    const output_never = try me.__.
                        dispatchIncomingToListenerIfAny(spec.NotifyIn, &msg, &mem_local, me);
                },

                .request => {
                    const output_maybe = try me.__.
                        dispatchIncomingToListenerIfAny(spec.RequestIn, &msg, &mem_local, me);
                    if (output_maybe) |json_out_bytes_in_shared_buf|
                        return me.onOutgoing(&mem_local.allocator, me.owner, json_out_bytes_in_shared_buf);
                },

                .response => {
                    if (me.__.handlers_responses) |*handlers_responses| {
                        for (handlers_responses.items[0..handlers_responses.len]) |*response_awaiter, i| {
                            if (options.json.eql(response_awaiter.req_id, msg.id.?.*)) {
                                defer {
                                    response_awaiter.mem_arena.deinit();
                                    _ = handlers_responses.swapRemove(i);
                                }
                                inline for (@typeInfo(spec.RequestOut).Union.fields) |*spec_field, idx| {
                                    if (response_awaiter.req_union_idx == idx) {
                                        const TResponse = @typeInfo(spec_field.field_type).Fn.return_type.?;

                                        const fn_arg: Result(TResponse) = if (msg.result_err) |err|
                                            Result(TResponse){ .err = err }
                                        else if (msg.result_ok) |ret|
                                            Result(TResponse){ .ok = try options.json.unmarshal(TResponse, &response_awaiter.mem_arena.allocator, ret) }
                                        else
                                            Result(TResponse){ .err = ResponseError{ .code = 0, .message = "unreachable" } }; // unreachable; // TODO! Zig currently segfaults here, check back later

                                        if (response_awaiter.ptr_state == 0) {
                                            const fn_then = @intToPtr(fn (void, Ctx(Result(TResponse))) anyerror!void, response_awaiter.ptr_fn);
                                            try fn_then(undefined, .{ .value = fn_arg, .mem = &response_awaiter.mem_arena.allocator, .inst = me.owner });
                                        } else {
                                            const fn_then = @intToPtr(fn (usize, Ctx(Result(TResponse))) anyerror!void, response_awaiter.ptr_fn);
                                            try fn_then(response_awaiter.ptr_state, .{ .value = fn_arg, .mem = &response_awaiter.mem_arena.allocator, .inst = me.owner });
                                        }
                                        return;
                                    }
                                }
                                return error.MsgUnknownReqId;
                            }
                        }
                    }
                    return error.MsgUnknownReqId;
                },
            }
        }

        const InternalState = struct {
            const ResponseAwaiter = struct {
                mem_arena: std.heap.ArenaAllocator,
                req_id: std.json.Value,
                req_union_idx: usize,
                ptr_state: usize,
                ptr_fn: usize,
            };

            shared_out_buf: ?std.ArrayList(u8) = null,
            handlers_notifies: [comptime zag.meta.memberCount(spec.NotifyIn)]?usize,
            handlers_requests: [comptime zag.meta.memberCount(spec.RequestIn)]?usize,
            handlers_responses: ?std.ArrayList(ResponseAwaiter) = null,

            fn dumpJsonValueToSharedBuf(me: *@This(), mem: *std.mem.Allocator, json_value: *const std.json.Value, comptime nesting_depth: comptime_int) !Str {
                if (me.shared_out_buf == null)
                    me.shared_out_buf = try std.ArrayList(u8).initCapacity(mem, 2048 * 1024);
                try @TypeOf(options.json).toBytes(&me.shared_out_buf.?, json_value, nesting_depth);
                return me.shared_out_buf.?.items[0..me.shared_out_buf.?.len];
            }

            fn dispatchIncomingToListenerIfAny(me: *@This(), comptime T: type, msg: var, mem_local: *std.heap.ArenaAllocator, parent: var) !?Str {
                const is_request = (T == spec.RequestIn);
                comptime std.debug.assert(is_request or T == spec.NotifyIn);
                const handlers = if (is_request) me.handlers_requests else me.handlers_notifies;
                inline for (@typeInfo(T).Union.fields) |*spec_field, idx| {
                    if (std.mem.eql(u8, spec_field.name, msg.method)) {
                        if (handlers[idx]) |fn_ptr_uint| {
                            const TParam = if (!is_request) spec_field.field_type else @typeInfo(spec_field.field_type).Fn.args[0].arg_type.?;
                            const TFunc = if (!is_request) (fn (Ctx(TParam)) anyerror!void) else (fn (Ctx(TParam)) anyerror!Result(@typeInfo(spec_field.field_type).Fn.return_type.?));

                            const param_val: TParam = if (msg.params) |params|
                                options.json.unmarshal(TParam, &mem_local.allocator, params) catch |err| {
                                    if (is_request) {
                                        const json_out_bytes_in_shared_buf = try me.dumpJsonValueToSharedBuf(parent.mem_alloc_for_arenas, &(try options.json.marshal(&mem_local.allocator, ResponseError{
                                            .code = @enumToInt(StandardErrorCodes.InvalidParams),
                                            .message = msg.method,
                                        })), options.json.nesting_depth_fallback);
                                        return json_out_bytes_in_shared_buf;
                                    }
                                    return err;
                                }
                            else if (TParam == void)
                                undefined
                            else if (@typeInfo(TParam) == .Optional)
                                null
                            else if (is_request) {
                                const json_out_bytes_in_shared_buf = try me.dumpJsonValueToSharedBuf(parent.mem_alloc_for_arenas, &(try options.json.marshal(&mem_local.allocator, ResponseError{
                                    .code = @enumToInt(StandardErrorCodes.InvalidParams),
                                    .message = msg.method,
                                })), options.json.nesting_depth_fallback);
                                return json_out_bytes_in_shared_buf;
                            } else
                                return error.MsgParamsMissing;

                            const fn_ptr = @intToPtr(TFunc, fn_ptr_uint);
                            const fn_ret = try fn_ptr(.{ .inst = parent.owner, .value = param_val, .mem = &mem_local.allocator });
                            if (!is_request)
                                return null
                            else {
                                const resp = fn_ret.toJsonRpcResponse(msg.id);
                                const json_out_bytes_in_shared_buf = try me.dumpJsonValueToSharedBuf(
                                    parent.mem_alloc_for_arenas,
                                    &(try options.json.marshal(&mem_local.allocator, resp)),
                                    options.json.nesting_depth_fallback,
                                );
                                return json_out_bytes_in_shared_buf;
                            }
                        }

                        // no userland listener for that type of incoming request / notification:
                        if (!is_request) {
                            std.debug.warn("No NotifyIn subscriber to: {s}, dropped.\n", .{msg.method});
                            return null;
                        } else {
                            const json_out_bytes_in_shared_buf = try me.dumpJsonValueToSharedBuf(parent.mem_alloc_for_arenas, &(try options.json.marshal(&mem_local.allocator, ResponseError{
                                .code = @enumToInt(StandardErrorCodes.InternalError),
                                .message = msg.method,
                            })), options.json.nesting_depth_fallback);
                            return json_out_bytes_in_shared_buf;
                        }
                    }
                }
                // method-name not known:
                if (is_request) {
                    const json_out_bytes_in_shared_buf = try me.dumpJsonValueToSharedBuf(parent.mem_alloc_for_arenas, &(try options.json.marshal(&mem_local.allocator, ResponseError{
                        .code = @enumToInt(StandardErrorCodes.MethodNotFound),
                        .message = msg.method,
                    })), options.json.nesting_depth_fallback);
                    return json_out_bytes_in_shared_buf;
                } else
                    return if (msg.method[0] == '_') null else error.MsgUnknownMethod;
            }
        };

        pub fn Ctx(comptime T: type) type {
            return struct {
                inst: *Owner,
                mem: *std.mem.Allocator,
                value: T,

                pub inline fn memArena(me: *const @This()) *std.heap.ArenaAllocator {
                    return @fieldParentPtr(std.heap.ArenaAllocator, "allocator", me.mem);
                }
            };
        }
    };
}
