const std = @import("std");

usingnamespace @import("../api.zig");
usingnamespace @import("../../jsonic/api.zig").Rpc;

pub fn setupCapabilitiesAndHandlers(lsp: *Server) void {
    lsp.api.onNotify(.initialized, onInitialized);
    lsp.api.onRequest(.shutdown, onShutdown);

    lsp.precis.capabilities.hoverProvider = .{ .enabled = true };
    lsp.api.onRequest(.textDocument_hover, onHover);

    lsp.precis.capabilities.completionProvider = .{
        .triggerCharacters = &[_]String{"."},
        .allCommitCharacters = &[_]String{"\t"},
        .resolveProvider = true,
    };
}

fn onInitialized(in: Server.In(InitializedParams)) !void {
    std.debug.warn("\nINIT\t{}\n", .{in.it});
    try in.ctx.api.notify(.window_showMessage, ShowMessageParams{
        .type__ = .Warning,
        .message = try std.fmt.allocPrint(in.mem, "So it's you... {} {}.", .{
            in.ctx.initialized.?.clientInfo.?.name,
            in.ctx.initialized.?.clientInfo.?.version,
        }),
    });
}

fn onShutdown(in: Server.In(void)) error{}!Result(void) {
    return Result(void){ .ok = {} };
}

fn onHover(in: Server.In(HoverParams)) !Result(?Hover) {
    const markdown = try std.fmt.allocPrint(in.mem, "Hover request:\n\n```zig\n{}\n```\n", .{in.it});
    return Result(?Hover){ .ok = Hover{ .contents = MarkupContent{ .value = markdown } } };
}
