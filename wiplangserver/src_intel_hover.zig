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
        for (locked.item.resolveds) |resolved|
            try markdowns.append(try toMarkDown(ctx.memArena(), &locked.item, resolved));
        if (markdowns.len == 0)
            try markdowns.append(try std.fmt.allocPrint(ctx.mem, "{}", .{locked.item.node.id}));
    }

    return Result(?Hover){
        .ok = Hover{
            .contents = MarkupContent{
                .value = try std.mem.
                    join(ctx.mem, "\n \n____\n \n", markdowns.toSliceConst()),
            },
        },
    };
}

/// foo __doc-comments__ go _here_,
/// one more line,
///
/// and another one,
/// for a quick `hover` try-out!
fn toMarkDown(mem: *std.heap.ArenaAllocator, context: *const SrcIntel.Resolved, cur_resolved: SrcIntel.AstResolved) !Str {
    switch (cur_resolved) {
        else => return try std.fmt.allocPrint(&mem.
            allocator, "no toMarkDown impl yet for `{}`", .{std.meta.activeTag(cur_resolved)}),

        .err_or_warning => |issue| return try std.fmt.allocPrint(&mem.
            allocator, "Problem with this `{}`:\n\n{}", .{ zag.mem.
            trimPrefix(u8, try std.fmt.allocPrint(&mem.allocator, "{}", .{issue.node_id}), "Id."), issue.detail }),

        .array => |arr| return try std.fmt.allocPrint(&mem.allocator, "{} array item(s)", .{arr.len}),

        .boolean => |b| return try std.fmt.allocPrint(&mem.allocator, "```zig\n{}: bool\n```\n", .{b}),

        .string => |str| return try std.fmt.allocPrint(&mem.
            allocator, "- {} byte(s) ({} ASCII)\n- {} UTF-8 rune(s)\n- {} line-break(s)\n- {} tab-stop(s)", .{ str.len, zag.util.asciiByteCount(str), if (zag.util.utf8RuneCount(str)) |n| n else |_| 0, zag.mem.count(str, '\n'), zag.mem.count(str, '\t') }),

        .float => |float| {
            var str: Str = "";
            const format_chars = "{d}{e}";
            comptime var i: usize = 0;
            inline while (i < format_chars.len) : (i += 3) {
                const fmt_preview = try std.fmt.allocPrint(&mem.allocator, format_chars[i .. i + 3], .{float});
                str = try std.fmt.allocPrint(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, format_chars[i .. i + 3], fmt_preview });
            }
            return str;
        },

        .int => |int| {
            var str: Str = "";
            const format_chars = "{d}{x}{b}";
            comptime var i: usize = 0;
            inline while (i < format_chars.len) : (i += 3) {
                const fmt_preview = try std.fmt.allocPrint(&mem.allocator, format_chars[i .. i + 3], .{int});
                str = try std.fmt.allocPrint(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, format_chars[i .. i + 3], fmt_preview });
            }
            if (int > 32 and int < 127) {
                const fmt_preview = try std.fmt.allocPrint(&mem.allocator, "{c}", .{@intCast(u8, int)});
                str = try std.fmt.allocPrint(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, "{c}", fmt_preview });
            }
            return str;
        },

        .loc_ref_same_src_file => |node| {
            const start = context.ast.tokens.at(node.firstToken()).start;
            const end = context.ast.tokens.at(node.lastToken()).end;
            var str: Str = "";
            if (try SrcIntel.astNodeDocComments(mem, context.ast, node)) |doc_comment_lines|
                if (doc_comment_lines.len != 0) {
                    for (doc_comment_lines) |doc_comment_line|
                        str = try std.fmt.allocPrint(&mem.allocator, "{s}{s}\n", .{ str, doc_comment_line });
                    str = try std.fmt.allocPrint(&mem.allocator, "{s}\n \n____\n \n", .{str});
                };
            str = try std.fmt.allocPrint(&mem.allocator, "{s}```zig\n{}\n```\n", .{ str, context.ast.source[start..end] });
            return str;
        },
    }
}
