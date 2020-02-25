usingnamespace @import("./_usingnamespace.zig");

pub fn onIssuePosCalc(mem_temp: *std.heap.ArenaAllocator, src: Str, tok_pos: [2]usize) ![]usize {
    if (try Range.initFromResliced(src, tok_pos[0], tok_pos[1])) |range|
        return make(&mem_temp.allocator, usize, .{ range.start.line, range.start.character, range.end.line, range.end.character });
    return &[_]usize{};
}

pub fn onFreshIssuesToPublish(mem_temp: *std.heap.ArenaAllocator, issues: std.StringHashMap([]SrcFiles.Issue)) !void {
    var iter = issues.iterator();
    while (iter.next()) |path_and_issues| {
        const payload = PublishDiagnosticsParams{
            .uri = try std.fmt.allocPrint(&mem_temp.allocator, "file://{s}", .{path_and_issues.key}),
            .diagnostics = try mem_temp.allocator.alloc(Diagnostic, path_and_issues.value.len),
        };
        for (path_and_issues.value) |*issue, i| {
            if (issue.pos_info.len == 4)
                payload.diagnostics[i] = .{
                    .range = .{ .start = .{ .line = issue.pos_info[0], .character = issue.pos_info[1] }, .end = .{ .line = issue.pos_info[2], .character = issue.pos_info[3] } },
                    .message = issue.message,
                    .source = @tagName(issue.scope),
                    .severity = switch (issue.scope) {
                        .load => .Warning,
                        .parse => .Information,
                        .zig_build => .Error,
                        .zig_test => .Warning,
                    },
                };
        }
        try @import("./main.zig").server.api.notify(.textDocument_publishDiagnostics, payload);
    }
}
