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
    return switch (resolved) {
        else => try std.fmt.allocPrint(&mem.allocator, "no toMarkDown impl yet for `{}`", .{std.meta.activeTag(resolved)}),
        .err_or_warning => |issue| try std.fmt.allocPrint(&mem.allocator, "Problem with this `{}`:\n\n{}", .{ zag.mem.
            trimPrefix(u8, try std.fmt.allocPrint(&mem.allocator, "{}", .{issue.node_id}), "Id."), issue.detail }),
    };
}
