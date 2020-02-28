usingnamespace @import("./_usingnamespace.zig");

pub fn onFreshIssuesToPublish(mem_temp: *std.heap.ArenaAllocator, issues: std.StringHashMap([]SrcFiles.Issue)) !void {
    var payloads = try std.ArrayList(PublishDiagnosticsParams).initCapacity(&mem_temp.allocator, issues.count());
    var iter = issues.iterator();
    while (iter.next()) |path_and_issues| {
        const payload = PublishDiagnosticsParams{
            .uri = try std.fmt.allocPrint(&mem_temp.allocator, "file://{s}", .{path_and_issues.key}),
            .diagnostics = try mem_temp.allocator.alloc(Diagnostic, path_and_issues.value.len),
        };
        for (path_and_issues.value) |*issue, i| {
            payload.diagnostics[i] = .{
                .range = .{ .start = .{ .line = issue.pos_info[0], .character = issue.pos_info[1] }, .end = .{ .line = issue.pos_info[2], .character = issue.pos_info[3] } },
                .message = issue.message,
                .source = switch (issue.scope) {
                    .load => "(file I/O)",
                    .parse => "(syntax)",
                    .zig_build => "zig build",
                },
                .severity = switch (issue.scope) {
                    .load => .Warning,
                    .parse => .Information,
                    .zig_build => .Error,
                },
            };
            if (issue.relateds.len != 0) {
                payload.diagnostics[i].relatedInformation = try mem_temp.allocator.alloc(DiagnosticRelatedInformation, issue.relateds.len);
                for (issue.relateds) |*related, idx|
                    payload.diagnostics[i].relatedInformation.?[idx] = .{
                        .message = related.message,
                        .location = .{
                            .uri = try std.fmt.allocPrint(&mem_temp.allocator, "file://{s}", .{related.location.full_path}),
                            .range = .{ .start = .{ .line = related.location.pos_info[0], .character = related.location.pos_info[1] }, .end = .{ .line = related.location.pos_info[2], .character = related.location.pos_info[3] } },
                        },
                    };
            }
        }
        try payloads.append(payload);
    }

    if (payloads.len > 0) {
        const lock = server.mutex.acquire();
        defer lock.release();

        for (payloads.items[0..payloads.len]) |_, i|
            try server.api.notify(.textDocument_publishDiagnostics, payloads.items[i]);
    }
}

var build_progress_token = ProgressToken{ .int = 0 };

pub fn onBuildRuns(situation: SrcFiles.OnBuildRuns) void {
    const lock = server.mutex.acquire();
    defer lock.release();
    switch (situation) {
        .begun => {
            build_progress_token.int = @intCast(i64, std.time.milliTimestamp());
            server.api.request(.window_workDoneProgress_create, {}, WorkDoneProgressCreateParams{ .token = build_progress_token }, struct {
                pub fn then(state: void, resp: Server.Ctx(Result(void))) error{}!void {}
            }) catch return;
            server.api.notify(.__progress, ProgressParams{
                .token = build_progress_token,
                .value = WorkDoneProgress{ .kind = "begin", .title = "zig build" },
            }) catch return;
        },
        .ended => {
            server.api.notify(.__progress, ProgressParams{
                .token = build_progress_token,
                .value = WorkDoneProgress{ .kind = "end", .title = "zig build" },
            }) catch return;
        },
        .cur_build_dir => |build_dir_path| {
            server.api.notify(.__progress, ProgressParams{
                .token = build_progress_token,
                .value = WorkDoneProgress{ .kind = "report", .title = "zig build", .message = build_dir_path },
            }) catch return;
        },
    }
}
