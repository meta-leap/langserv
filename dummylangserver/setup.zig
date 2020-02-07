const std = @import("std");

usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").Rpc;

pub fn setupCapabilitiesAndHandlers(srv: *Server) void {
    srv.api.onNotify(.initialized, onInitialized);
    srv.api.onRequest(.shutdown, onShutdown);

    srv.precis.capabilities.hoverProvider = .{ .enabled = true };
    srv.api.onRequest(.textDocument_hover, onHover);

    srv.precis.capabilities.completionProvider = .{
        .triggerCharacters = &[_]String{"."},
        .allCommitCharacters = &[_]String{"\t"},
        .resolveProvider = true,
    };
    srv.api.onRequest(.textDocument_completion, onCompletion);
    srv.api.onRequest(.completionItem_resolve, onCompletionResolve);
}

fn onInitialized(ctx: Server.Ctx(InitializedParams)) !void {
    std.debug.warn("\nINIT\t{}\n", .{ctx.value});
    try ctx.inst.api.notify(.window_showMessage, ShowMessageParams{
        .type__ = .Warning,
        .message = try std.fmt.allocPrint(ctx.mem, "So it's you... {} {}.", .{
            ctx.inst.initialized.?.clientInfo.?.name,
            ctx.inst.initialized.?.clientInfo.?.version,
        }),
    });
}

fn onShutdown(ctx: Server.Ctx(void)) error{}!Result(void) {
    return Result(void){ .ok = {} };
}

fn onHover(ctx: Server.Ctx(HoverParams)) !Result(?Hover) {
    const markdown = try std.fmt.allocPrint(ctx.mem, "Hover request:\n\n```zig\n{}\n```\n", .{ctx.value});
    return Result(?Hover){ .ok = Hover{ .contents = MarkupContent{ .value = markdown } } };
}

fn onCompletion(ctx: Server.Ctx(CompletionParams)) !Result(?CompletionList) {
    var cmpls = try std.ArrayList(CompletionItem).initCapacity(ctx.mem, 8);
    return Result(?CompletionList){ .ok = .{ .items = cmpls.items[0..cmpls.len] } };
}

fn onCompletionResolve(ctx: Server.Ctx(CompletionItem)) error{}!Result(CompletionItem) {
    return Result(CompletionItem){ .ok = ctx.value };
}
