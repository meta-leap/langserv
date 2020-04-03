const std = @import("std");
usingnamespace @import("../zag/zag.zig");
const jsonic = @import("./jsonic.zig");
usingnamespace jsonic.Rpc;

const Owner = void;

const print = std.debug.warn;
const fmt_ritzy = "\n\n=== {} ===\n{}\n";
var mem_demo = std.heap.ArenaAllocator.init(std.heap.page_allocator);

const our_api_spec = Spec{
    .newReqId = nextReqId,

    .RequestIn = union(enum) {
        negate: fn (i64) i64,
        hostName: fn (void) []u8,
        envVarValue: fn (Str) Str,
    },

    .RequestOut = union(enum) {
        pow2: fn (i64) i64,
        rnd: fn (void) f32,
        add: fn (?AddArgs) ?i64,
    },

    .NotifyIn = union(enum) {
        timeInfo: TimeInfo,
        shuttingDown: void,
    },

    .NotifyOut = union(enum) {
        envVarNames: []Str,
        shoutOut: bool,
    },
};

const OurRpcApi = Api(Owner, our_api_spec, Options{});

fn onOutput(mem: *std.mem.Allocator, owner: *Owner, json_bytes: Str) void {
    print(fmt_ritzy, .{ "Outgoing JSON", json_bytes });
}

test "demo" {
    defer mem_demo.deinit();

    const time_now = @intCast(i64, std.time.milliTimestamp()); // want something guaranteed to be runtime-not-comptime

    var our_rpc = OurRpcApi{
        .owner = &Owner{},
        .onOutgoing = onOutput,
        .mem_alloc_for_arenas = std.heap.page_allocator,
    };
    defer our_rpc.deinit();

    // that was the SETUP, now some USAGE:

    var json_out_str: Str = undefined;
    const State = struct {
        note: Str,
    };

    our_rpc.onNotify(.timeInfo, on_timeInfo);
    our_rpc.onNotify(.shuttingDown, on_shuttingDown);
    our_rpc.onRequest(.negate, on_negate);
    our_rpc.onRequest(.envVarValue, on_envVarValue);
    our_rpc.onRequest(.hostName, on_hostName);

    try our_rpc.incoming("{ \"id\": 1, \"method\": \"envVarValue\", \"params\": \"GOPATH\" }");
    try our_rpc.incoming("{ \"id\": 2, \"method\": \"hostName\" }");
    try our_rpc.incoming("{ \"id\": 3, \"method\": \"negate\", \"params\": 42.42 }");

    try our_rpc.request(.rnd, State{ .note = "rnd gave:" }, {}, struct {
        pub fn then(state: *State, ctx: OurRpcApi.Ctx(Result(f32))) error{}!void {
            print(fmt_ritzy, .{ state.note, ctx.value });
        }
    });

    try our_rpc.incoming("{ \"method\": \"timeInfo\", \"params\": {\"start\": 123, \"now\": 321} }");
    try our_rpc.incoming("{ \"id\": \"demo_req_id_1\", \"result\": 123.456 }");

    try our_rpc.request(.pow2, &State{ .note = "pow2 gave:" }, time_now, struct {
        pub fn then(state: *State, ctx: OurRpcApi.Ctx(Result(i64))) error{}!void {
            print(fmt_ritzy, .{ state.note, ctx.value });
        }
    });

    try our_rpc.request(.add, &State{ .note = "add gave:" }, AddArgs{ .a = 42, .b = 23 }, struct {
        pub fn then(state: *State, ctx: OurRpcApi.Ctx(Result(?i64))) error{}!void {
            print(fmt_ritzy, .{ state.note, ctx.value });
        }
    });

    try our_rpc.incoming("{ \"id\": \"demo_req_id_3\", \"result\": 65 }");

    try our_rpc.notify(.shoutOut, true);
    try our_rpc.notify(.envVarNames, try demo_envVarNames());

    try our_rpc.incoming("{ \"id\": \"demo_req_id_2\", \"error\": { \"code\": 12345, \"message\": \"No pow2 to you!\" } }");
    try our_rpc.incoming("{ \"method\": \"shuttingDown\" }");

    var tmp = jsonic.AnyValue{ .object = &[_]jsonic.AnyValue.Property{.{ .name = "foo", .value = .{ .string = "BarBaz" } }} };
    print("\n{}\n{}\n", .{ tmp.get("foo"), tmp.eql(tmp) });
}

var req_id_counter: usize = 0;
fn nextReqId(mem: *std.mem.Allocator) !std.json.Value {
    req_id_counter += 1;
    const str = try std.fmt.allocPrint(mem, "demo_req_id_{d}", .{req_id_counter});
    return std.json.Value{ .String = str };
}

const TimeInfo = struct {
    start: i64,
    now: ?u64,
};

fn on_timeInfo(ctx: OurRpcApi.Ctx(TimeInfo)) error{}!void {
    print(fmt_ritzy, .{ "on_timeInfo", ctx.value });
}

fn on_shuttingDown(ctx: OurRpcApi.Ctx(void)) error{}!void {
    print(fmt_ritzy, .{ "on_shuttingDown", ctx.value });
}

fn on_negate(ctx: OurRpcApi.Ctx(i64)) error{}!Result(i64) {
    return Result(i64){ .err = .{ .code = 12321, .message = "not implemented: negate" } };
    // return .{ .ok = -ctx.value };
}

fn on_hostName(ctx: OurRpcApi.Ctx(void)) !Result([]u8) {
    var buf_hostname: [std.os.HOST_NAME_MAX]u8 = undefined;
    return if (std.os.gethostname(&buf_hostname)) |host|
        .{ .ok = try std.mem.dupe(ctx.mem, u8, host) }
    else |err|
        .{ .err = .{ .code = 54321, .message = @errorName(err) } };
}

fn on_envVarValue(ctx: OurRpcApi.Ctx(Str)) error{}!Result(Str) {
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (pair.len > ctx.value.len and pair[ctx.value.len] == '=' and std.mem.eql(u8, pair[0..ctx.value.len], ctx.value))
            return Result(Str){ .ok = pair[ctx.value.len + 1 .. pair.len - 1] };
    }
    return Result(Str){ .err = .{ .code = 12345, .message = ctx.value } };
}

fn demo_envVarNames() ![]Str {
    var ret = try std.ArrayList(Str).initCapacity(&mem_demo.allocator, std.os.environ.len);
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (std.mem.indexOfScalar(u8, pair, '=')) |pos|
            try ret.append(pair[0..pos]);
    }
    return ret.toOwnedSlice();
}

const AddArgs = struct {
    a: i64,
    b: i64,
};
