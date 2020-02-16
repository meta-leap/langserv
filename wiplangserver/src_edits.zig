usingnamespace @import("./_usingnamespace.zig");

pub fn onFormat(ctx: Server.Ctx(DocumentFormattingParams)) !Result(?[]TextEdit) {
    return formatted(ctx.mem, ctx.value.textDocument.uri);
}

pub fn onFormatOnType(ctx: Server.Ctx(DocumentOnTypeFormattingParams)) !Result(?[]TextEdit) {
    return formatted(ctx.mem, ctx.value.TextDocumentPositionParams.textDocument.uri);
}

fn formatted(mem: *std.mem.Allocator, uri: Str) !Result(?[]TextEdit) {
    const src_file_absolute_path = lspUriToFilePath(uri);
    if (zsess.src_files.getByFullPath(src_file_absolute_path)) |src_file|
        if (try src_file.formatted(mem)) |formatted_src| {
            var edit = TextEdit{
                .newText = formatted_src,
                .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = std.math.maxInt(i32), .character = 0 } },
            };
            return Result(?[]TextEdit){ .ok = try std.mem.dupe(mem, TextEdit, &[_]TextEdit{edit}) };
        };
    return Result(?[]TextEdit){ .ok = null };
}
