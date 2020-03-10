usingnamespace @import("./_usingnamespace.zig");

const strfmt = std.fmt.allocPrint;

pub fn onHover(ctx: Server.Ctx(HoverParams)) !Result(?Hover) {
    const src_file_abs_path = lspUriToFilePath(ctx.value.TextDocumentPositionParams.textDocument.uri);
    var markdowns = try std.ArrayList(Str).initCapacity(ctx.mem, 4);

    if (try zsess.src_intel.resolve(ctx.memArena(), .{
        .full_path = src_file_abs_path,
        .pos_info = &[2]usize{
            ctx.value.TextDocumentPositionParams.position.line,
            ctx.value.TextDocumentPositionParams.position.character,
        },
    })) |*locked| {
        defer locked.deinitAndUnlock();
        for (locked.item.resolveds) |resolved|
            try markdowns.append(try toMarkDown(ctx.memArena(), &locked.item, resolved));
        if (markdowns.len == 0) switch (locked.item.node.id) {
            else => try markdowns.append(try strfmt(ctx.mem, "{}", .{locked.item.node.id})),
            .BuiltinCall => if (locked.item.node.cast(std.zig.ast.Node.BuiltinCall)) |this_bcall| {
                const name = std.mem.trimLeft(u8, locked.item.the.ast.tokenSlicePtr(locked.item.the.ast.tokens.at(this_bcall.builtin_token)), "@");
                if (try zsess.zig_install.langrefHtmlFileSrcSnippet(ctx.memArena(), name)) |descr_snippet|
                    try markdowns.append(try zag.util.stripMarkupTags(ctx.mem, std.mem.trim(u8, try zag.mem.replaceAny(
                        ctx.mem,
                        try strfmt(ctx.mem, "{s}", .{descr_snippet}),
                        &[_][2]Str{
                            [2]Str{ "<code class=\"zig\">", "`" },
                            [2]Str{ "</code>", "`" },
                            [2]Str{ "&quot;", "\"" },
                        },
                    ), " \t\n\r")));
            },
        };
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
fn toMarkDown(mem: *std.heap.ArenaAllocator, _: *const SrcIntel.Resolved, cur_resolved: zast.Resolved) !Str {
    switch (cur_resolved) {
        else => return try strfmt(&mem.
            allocator, "no toMarkDown impl yet for `{}`", .{std.meta.activeTag(cur_resolved)}),

        .err_or_warning => |issue_message| return issue_message,

        .loc_ref => |*loc_ref| {
            var str: Str = "";
            if (try zast.nodeDocComments(mem, loc_ref.ctx.ast, loc_ref.node)) |doc_comment_lines|
                if (doc_comment_lines.len != 0) {
                    for (doc_comment_lines) |doc_comment_line|
                        str = try strfmt(&mem.allocator, "{s}{s}\n", .{ str, doc_comment_line });
                    str = try strfmt(&mem.allocator, "{s}\n \n____\n \n", .{str});
                };

            var start = loc_ref.ctx.ast.tokens.at(loc_ref.node.firstToken()).start;
            var end = loc_ref.ctx.ast.tokens.at(loc_ref.node.lastToken()).end;
            switch (loc_ref.node.id) {
                else => {},
                .PointerIndexPayload, .PointerPayload, .Payload => {
                    if (try zast.pathToNode(loc_ref.ctx, .{ .node = loc_ref.node })) |node_path|
                        start = loc_ref.ctx.ast.tokens.at(node_path[node_path.len - 2].firstToken()).start;
                },
            }
            str = try strfmt(&mem.allocator, "{s}```zig\n{}\n```\n", .{ str, loc_ref.ctx.ast.source[start..end] });
            return str;
        },

        .type_desc => |type_desc| return try strfmt(&mem.allocator, "```zig\n{s}\n```\n", .{try typeStr(&mem.allocator, &type_desc)}),

        .lit_arr => |arr| return try strfmt(&mem.allocator, "{} array item(s)", .{arr.len}),

        .lit_bool => |b| return try strfmt(&mem.allocator, "```zig\n{}: bool\n```\n", .{b}),

        .lit_str => |str| return try strfmt(&mem.
            allocator, "- {} byte(s) ({} ASCII)\n- {} UTF-8 rune(s)\n- {} line-break(s)\n- {} tab-stop(s)", .{ str.len, zag.util.asciiByteCount(str), if (zag.util.utf8RuneCount(str)) |n| n else |_| 0, zag.mem.count(str, '\n'), zag.mem.count(str, '\t') }),

        .lit_float => |float| {
            var str: Str = "";
            const format_chars = "{d}{e}";
            comptime var i: usize = 0;
            inline while (i < format_chars.len) : (i += 3) {
                const fmt_preview = try strfmt(&mem.allocator, format_chars[i .. i + 3], .{float});
                str = try strfmt(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, format_chars[i .. i + 3], fmt_preview });
            }
            {
                const fmt_preview = try strfmt(&mem.allocator, "{d:.3}", .{float});
                str = try strfmt(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, "{d:.3}", fmt_preview });
            }
            return str;
        },

        .lit_int => |int| {
            var str: Str = "";
            const format_chars = "{d}{x}{b}";
            comptime var i: usize = 0;
            inline while (i < format_chars.len) : (i += 3) {
                const fmt_preview = try strfmt(&mem.allocator, format_chars[i .. i + 3], .{int});
                str = try strfmt(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, format_chars[i .. i + 3], fmt_preview });
            }
            if (int > 32 and int < 127) {
                const fmt_preview = try strfmt(&mem.allocator, "{c}", .{@intCast(u8, int)});
                str = try strfmt(&mem.allocator, "{s}- `{s}` &rarr; `{s}`\n", .{ str, "{c}", fmt_preview });
            }
            return str;
        },
    }
}

fn typeStr(mem: *std.mem.Allocator, type_desc: *const zast.Resolved.TypeDesc) error{OutOfMemory}!Str {
    switch (type_desc.*) {
        .prim => |prim| return @tagName(prim),

        .int => |int| return if (int.bit_width) |bit_width|
            try strfmt(mem, "{c}{d}", .{ if (int.unsigned) @as(u8, 'u') else @as(u8, 'i'), bit_width })
        else
            @as(Str, "comptime_int"),

        .float => |float| return if (float.bit_width) |bit_width|
            try strfmt(mem, "f{d}", .{bit_width})
        else
            @as(Str, "comptime_float"),

        .wrap => |wrap| return try strfmt(mem, "{s}{s}{s}", .{ switch (wrap.which) {
            .arr => |size| @as(Str, try strfmt(mem, "[{d}]", .{size})),
            .opt => @as(Str, "?"),
            .ptr => @as(Str, "*"),
            .slice => @as(Str, "[]"),
        }, @as(Str, if (wrap.@"const") "const " else ""), try typeStr(mem, wrap.of) }),

        .container => |cont| {
            var str: Str = try strfmt(mem, "{s} {c}\n", .{ cont.kind, '{' });
            str = try strfmt(mem, "{s}\t// TODO: fill in fields quoted from src loc-ref..\n", .{str});
            return try strfmt(mem, "{s}{c}", .{ str, '}' });
        },
    }
}
