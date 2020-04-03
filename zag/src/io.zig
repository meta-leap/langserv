const std = @import("std");
usingnamespace @import("../zag.zig");

pub fn HttpishHeaderBodySplittingReader(comptime InStreamType: type) type {
    const HttpishHeaderBodyPair = struct {
        headers_part: Str,
        body_part: Str,
    };

    return struct {
        in_stream: InStreamType,
        perma_buf: *std.ArrayList(u8),

        keep_from_idx: ?usize = null,

        pub fn next(me: *@This()) !?HttpishHeaderBodyPair {
            if (me.keep_from_idx) |keep_from_idx| {
                const keep_len = me.perma_buf.len - keep_from_idx;
                std.mem.copy(u8, me.perma_buf.items[0..keep_len], me.perma_buf.items[keep_from_idx .. keep_from_idx + keep_len]);
                me.perma_buf.len = keep_len;
                me.keep_from_idx = null;
            }

            var got_content_len: ?usize = null;
            while (true) {
                const so_far = me.perma_buf.items[0..me.perma_buf.len];

                if (got_content_len == null)
                    if (std.mem.indexOf(u8, so_far, "Content-Length:")) |pos|
                        if (pos == 0 or me.perma_buf.items[pos - 1] == '\n') {
                            const pos_start = pos + "Content-Length:".len;
                            if (std.mem.indexOfScalarPos(u8, so_far, pos_start, '\n')) |pos_newline| {
                                const str_content_len = std.mem.trim(u8, so_far[pos_start..pos_newline], " \t\r");
                                got_content_len = try std.fmt.parseUnsigned(usize, str_content_len, 10); // fair to fail here: cannot realistically "recover" from a bad `Content-Length:`
                            }
                        };

                if (got_content_len) |content_len| {
                    if (std.mem.indexOf(u8, so_far, "\r\n\r\n")) |pos| {
                        const pos_body_start = pos + 4;
                        const pos_body_end = pos_body_start + content_len;
                        if (so_far.len >= pos_body_end) {
                            me.keep_from_idx = pos_body_end;
                            return HttpishHeaderBodyPair{
                                .headers_part = so_far[0..pos],
                                .body_part = so_far[pos_body_start..pos_body_end],
                            };
                        }
                    }
                    try me.perma_buf.ensureCapacity(content_len);
                }

                if ((1 + me.perma_buf.len) >= me.perma_buf.capacity())
                    try me.perma_buf.ensureCapacity(8 + ((me.perma_buf.capacity() * 3) / 2));
                const num_bytes = try me.in_stream.read(me.perma_buf.items[me.perma_buf.len..]);
                if (num_bytes > 0)
                    me.perma_buf.len += num_bytes
                else
                    return null;
            }
        }
    };
}
