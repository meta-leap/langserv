const std = @import("std");

test "" {
    const lsp = @import("./api.zig");

    _ = lsp.api_spec;
    _ = lsp.serveForever;
}
