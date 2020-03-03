usingnamespace @import("./_usingnamespace.zig");

pub fn lookup(comptime TRetLocs: type, mem: *std.heap.ArenaAllocator, lookup_kind: SrcIntel.Lookup, src_file_uri: Str, pos: Position) !Result(?TRetLocs) {
    const locs = try zsess.src_intel.lookup(mem, lookup_kind, .{
        .full_path = lspUriToFilePath(src_file_uri),
        .pos_info = &[2]usize{ pos.line, pos.character },
    });
    const results: TRetLocs = .{ .locations = try mem.allocator.alloc(Location, locs.len) };
    for (locs) |*loc, i|
        results.locations[i] = .{
            .uri = try std.fmt.allocPrint(&mem.allocator, "file://{s}", .{loc.full_path}),
            .range = .{
                .start = .{ .line = loc.pos_info[0], .character = loc.pos_info[1] },
                .end = .{ .line = loc.pos_info[2], .character = loc.pos_info[3] },
            },
        };
    return Result(?TRetLocs){ .ok = results };
}

pub fn onDefs(ctx: Server.Ctx(DefinitionParams)) !Result(?Locations) {
    return lookup(Locations, ctx.memArena(), .Definitions, ctx.value.
        TextDocumentPositionParams.textDocument.uri, ctx.value.TextDocumentPositionParams.position);
}
