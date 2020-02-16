usingnamespace @import("./_usingnamespace.zig");

pub fn onSymbols(ctx: Server.Ctx(DocumentSymbolParams)) !Result(?DocumentSymbols) {
    var symbols = try std.ArrayList(DocumentSymbol).initCapacity(ctx.mem, 512);
    const src_file_abs_path = lspUriToFilePath(ctx.value.textDocument.uri);

    comptime var i: usize = 0;
    inline for (@typeInfo(SymbolKind).Enum.fields) |*enum_field| {
        try symbols.append(DocumentSymbol{
            .name = enum_field.name,
            .detail = try std.fmt.allocPrint(ctx.mem, "{s}.{s} = {d}", .{ @typeName(SymbolKind), enum_field.name, enum_field.value }),
            .kind = @intToEnum(SymbolKind, enum_field.value),
            .range = Range{ .start = .{ .character = 0, .line = i }, .end = .{ .character = 22, .line = i } },
            .selectionRange = Range{ .start = .{ .character = 0, .line = i }, .end = .{ .character = 22, .line = i } },
        });
        i += 1;
    }

    return Result(?DocumentSymbols){ .ok = .{ .hierarchy = symbols.toSliceConst() } };
}
