usingnamespace @import("./_usingnamespace.zig");

pub fn onHover(ctx: Server.Ctx(HoverParams)) !Result(?Hover) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.TextDocumentPositionParams.textDocument.uri);
    var markdowns = try std.ArrayList(Str).initCapacity(ctx.mem, 4);
    if (try zsess.src_intel.resolve(ctx.memArena(), .{
        .full_path = src_file_abs_path,
        .pos_info = &[2]usize{
            ctx.value.TextDocumentPositionParams.position.line,
            ctx.value.TextDocumentPositionParams.position.character,
        },
    })) |locked| {
        defer locked.held.release();
        try markdowns.append(try std.fmt.allocPrint(ctx.mem, "{}", .{locked.item.node.id}));
        for (locked.item.resolveds) |resolved|
            try markdowns.append(try toMarkDown(ctx.memArena(), resolved));
    }

    return Result(?Hover){
        .ok = Hover{
            .contents = MarkupContent{
                .value = try std.mem.
                    join(ctx.mem, "\n\n____\n\n", markdowns.toSliceConst()),
            },
        },
    };
}

fn toMarkDown(mem: *std.heap.ArenaAllocator, resolved: SrcIntel.AstResolved) !Str {
    switch (resolved) {
        else => return try std.fmt.allocPrint(&mem.
            allocator, "no toMarkDown impl yet for `{}`", .{std.meta.activeTag(resolved)}),
        .err_or_warning => |issue| return try std.fmt.allocPrint(&mem.
            allocator, "Problem with this `{}`:\n\n{}", .{ zag.mem.
            trimPrefix(u8, try std.fmt.allocPrint(&mem.allocator, "{}", .{issue.node_id}), "Id."), issue.detail }),
        .string => |str| return try std.fmt.allocPrint(&mem.
            allocator, "{} bytes; {} UTF-8 runes", .{ str.len, if (zag.util.utf8RuneCount(str)) |n| n else |_| 0 }),
        .uint => |uint| {
            var str: Str = "";
            const format_chars = "{d}{x}{b}";
            comptime var i: usize = 0;
            inline while (i < format_chars.len) : (i += 3) {
                const fmt_preview = try std.fmt.allocPrint(&mem.allocator, format_chars[i .. i + 3], .{uint});
                str = try std.fmt.allocPrint(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, format_chars[i .. i + 3], fmt_preview });
            }
            if (uint > 32 and uint < 127) {
                const fmt_preview = try std.fmt.allocPrint(&mem.allocator, "{c}", .{@intCast(u8, uint)});
                str = try std.fmt.allocPrint(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, "{c}", fmt_preview });
            }
            return str;
        },
    }
}
