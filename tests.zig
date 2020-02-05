const std = @import("std");

test "" {
    const lsp = @import("./api.zig");

    _ = lsp.api_server_side;
    _ = lsp.Server.forever;
}
