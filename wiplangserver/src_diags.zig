usingnamespace @import("./_usingnamespace.zig");

pub fn onIssuePosCalc(mem_temp: *std.heap.ArenaAllocator, src: Str, tok_pos: [2]usize, kind: SrcFiles.Issue.PosInfoKind) ![]usize {
    const range = switch (kind) {
        .byte_offsets_0_based_range => try Range.initFromResliced(src, tok_pos[0], tok_pos[1]),
        .line_and_col_1_based_pos => pos2range: {
            const pos = Position{ .line = tok_pos[0] - 1, .character = tok_pos[1] - 1 };
            break :pos2range Range{ .start = pos, .end = pos };
        },
    };
    return make(&mem_temp.allocator, usize, .{ range.start.line, range.start.character, range.end.line, range.end.character });
}

pub fn onFreshIssuesToPublish(mem_temp: *std.heap.ArenaAllocator, issues: std.StringHashMap([]SrcFiles.Issue)) !void {
    var payloads = try std.ArrayList(PublishDiagnosticsParams).initCapacity(&mem_temp.allocator, issues.count());
    var iter = issues.iterator();
    while (iter.next()) |path_and_issues| {
        const payload = PublishDiagnosticsParams{
            .uri = try std.fmt.allocPrint(&mem_temp.allocator, "file://{s}", .{path_and_issues.key}),
            .diagnostics = try mem_temp.allocator.alloc(Diagnostic, path_and_issues.value.len),
        };
        for (path_and_issues.value) |*issue, i|
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
