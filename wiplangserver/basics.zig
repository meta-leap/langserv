usingnamespace @import("./_usingnamespace.zig");

pub var zsess = Session{};
pub var mem_alloc = if (std.builtin.mode == .Debug) &mem_alloc_debug.allocator else std.heap.allocator;
pub var mem_alloc_debug = zag.debug.Allocator.init(std.heap.page_allocator);

pub inline fn lspUriToFilePath(uri: Str) Str {
    return zag.mem.trimPrefix(u8, uri, "file://");
}

// could later prepend timestamps, or turn conditional on std.built.mode, etc.
pub inline fn logToStderr(comptime fmt: Str, args: var) void {
    std.debug.warn(fmt, args);
}

pub inline fn rangesFor(named_decl: *SrcFile.Intel.NamedDecl, in_src: Str) !?struct {
    full: Range = null, // TODO: Zig should compileError here! but in minimal repro it does. so leave it for now, but report before Zig 1.0.0 if it doesn't get fixed by chance in the meantime
    name: ?Range = null,
    brief: ?Range = null,
    brief_pref: ?Range = null,
    brief_suff: ?Range = null,

    pub fn strFromAnyOf(me: *const @This(), comptime field_names_to_try: []Str, in_src: Str) ?Str {
        inline for (field_names_to_try) |field_name|
            if (@field(me, field_name)) |range| {
                if (range.sliceConst(in_src)) |maybe_str| {
                    if (maybe_str) |str|
                        return str;
                } else |_| {}
            };
        return null;
    }
} {
    const TRet = @typeInfo(@typeInfo(@TypeOf(rangesFor).ReturnType).ErrorUnion.payload).Optional.child;
    var ret = TRet{
        .full = (try Range.initFromSlice(in_src, named_decl.
            pos.full.start, named_decl.pos.full.end)) orelse return null,
    };
    if (named_decl.pos.name) |pos_name|
        ret.name = try Range.initFromSlice(in_src, pos_name.start, pos_name.end);
    if (named_decl.pos.brief) |pos_brief|
        ret.brief = try Range.initFromSlice(in_src, pos_brief.start, pos_brief.end);
    if (named_decl.pos.brief_pref) |pos_brief_pref|
        ret.brief_pref = try Range.initFromSlice(in_src, pos_brief_pref.start, pos_brief_pref.end);
    if (named_decl.pos.brief_suff) |pos_brief_suff|
        ret.brief_suff = try Range.initFromSlice(in_src, pos_brief_suff.start, pos_brief_suff.end);
    return ret;
}
