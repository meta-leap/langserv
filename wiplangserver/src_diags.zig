usingnamespace @import("./_usingnamespace.zig");

pub fn onFreshIssuesToPublish(mem_temp: *std.heap.ArenaAllocator, issues: std.StringHashMap([]SrcFiles.Issue)) !void {
    var iter = issues.iterator();
    while (iter.next()) |path_and_issues| {
        const payload = PublishDiagnosticsParams{
            .uri = try std.fmt.allocPrint(&mem_temp.allocator, "file://{s}", .{path_and_issues.key}),
            .diagnostics = try mem_temp.allocator.alloc(Diagnostic, path_and_issues.value.len),
        };
        for (path_and_issues.value) |*issue, i| {
            payload.diagnostics[i] = .{
                .range = .{ .start = .{ .line = 0, .character = 0 }, .end = .{ .line = 1, .character = 0 } },
                .message = issue.message,
                .source = @tagName(issue.scope),
                .severity = switch (issue.scope) {
                    .load => .Information,
                    .parse => .Hint,
                    .zig_build => .Error,
                    .zig_test => .Warning,
                },
            };
        }
        if (payload.diagnostics.len != 0)
            try @import("./main.zig").server.api.notify(.textDocument_publishDiagnostics, payload);
    }
}
