const std = @import("std");
usingnamespace std.testing;
usingnamespace @import("./zag.zig");

test "" {
    var mem = zag.debug.Allocator.init(std.heap.page_allocator);
    defer mem.report("\n\n");

    var items = &[_][]u8{ &[_]u8{ 'c', 'f', 'b', 'r' }, &[_]u8{'a'}, &[_]u8{ 't', 'd', 'n' } };
    const perms = try zag.mem.inOrderPermutations(u8, &mem.allocator, items);
    defer mem.allocator.free(perms);
    expect(perms.len == 3 * 12);
    expect(std.mem.eql(u8, perms[0..3], "cat"));
    expect(std.mem.eql(u8, perms[3..6], "fat"));
    expect(std.mem.eql(u8, perms[6..9], "bat"));
    expect(std.mem.eql(u8, perms[9..12], "rat"));
    expect(std.mem.eql(u8, perms[12..15], "cad"));
    expect(std.mem.eql(u8, perms[15..18], "fad"));
    expect(std.mem.eql(u8, perms[18..21], "bad"));
    expect(std.mem.eql(u8, perms[21..24], "rad"));
    expect(std.mem.eql(u8, perms[24..27], "can"));
    expect(std.mem.eql(u8, perms[27..30], "fan"));
    expect(std.mem.eql(u8, perms[30..33], "ban"));
    expect(std.mem.eql(u8, perms[33..36], "ran"));

    var slice3x = of([2]Str, .{ .{ "foo", "bar" }, .{ "baz", "goof" }, .{ "x", "y" } });
    expect(std.mem.eql(u8, slice3x[0][0], "foo"));
    expect(std.mem.eql(u8, slice3x[0][1], "bar"));
    expect(std.mem.eql(u8, slice3x[1][0], "baz"));
    expect(std.mem.eql(u8, slice3x[1][1], "goof"));
    expect(std.mem.eql(u8, slice3x[2][0], "x"));
    expect(std.mem.eql(u8, slice3x[2][1], "y"));

    {
        var repl_in: Str = "foo bar baz";
        var repl_out: Str = undefined;

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "bar", "noice", .once);
        expect(std.mem.eql(u8, "foo noice baz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "o", "oo", .once);
        expect(std.mem.eql(u8, "foooo bar baz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "a", "", .once);
        expect(std.mem.eql(u8, "foo br bz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "_", "____", .once);
        expect(std.mem.eql(u8, "foo bar baz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "f", "f", .once);
        expect(std.mem.eql(u8, "foo bar baz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, " bar ", " bar ", .once);
        expect(std.mem.eql(u8, "foo bar baz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "foo bar baz", "foo bar baz", .once);
        expect(std.mem.eql(u8, "foo bar baz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "", "foo bar baz", .once);
        expect(std.mem.eql(u8, "foo bar baz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replace(&mem.allocator, repl_in, "oo bar ba", "", .once);
        expect(std.mem.eql(u8, "fz", repl_out));
        mem.allocator.free(repl_out);

        repl_out = try zag.mem.replaceAny(&mem.allocator, repl_in, of([2]Str, .{
            .{ "f", "z" },
            .{ "z", "y" },
            .{ "r", "rt" },
        }));
        expect(std.mem.eql(u8, "zoo bart bay", repl_out));
        mem.allocator.free(repl_out);
    }

    expect(zag.meta.WhatArrayList(std.ArrayList(u77)) == u77);
    expect(zag.meta.isTypeHashMapLikeDuckwise(std.StringHashMap([]Str)));
    _ = zag.mem.zeroed(std.json.Value);
    _ = zag.mem.fullDeepCopyTo;
    _ = zag.mem.fullDeepFreeFrom;
    _ = zag.fs.TmpDir.init;
    _ = zag.fs.TmpDir.deinit;
    _ = zag.mem.reoccursLater;
    _ = zag.mem.deepValueEquality;
    _ = zag.mem.indexOf;
    _ = zag.mem.indexOfLast;
    _ = zag.mem.dupeAppend;
    _ = zag.mem.times;
    const Tree = zag.Flatree(struct {
        x: u7,
        y: i77,
    });
    _ = Tree.Node;
    _ = Tree.Iterator;
    _ = Tree.Iterator.next;
    _ = Tree.subNodesOf;
    _ = Tree.find;
    _ = Tree.haveAny;
    _ = Tree.toOrderedList;
    _ = Tree.remove;
    _ = Tree.add;
    _ = Tree.moveSubNodesToNewParent;

    const count = 42;

    var mem_stream = std.io.SliceInStream.init("Line 1\r\nContent-Length: 8\r\nLine 22\r\n\r\nLine 333NextHeaderLine\r\n" ** count);
    var splitter = zag.io.HttpishHeaderBodySplittingReader(@TypeOf(&mem_stream.stream)){
        .perma_buf = &(try std.ArrayList(u8).initCapacity(&mem.allocator, 0)),
        .in_stream = &mem_stream.stream,
    };
    defer splitter.perma_buf.deinit();
    var i: usize = 0;
    while (try splitter.next()) |headers_and_body| : (i += 1)
        expect(std.mem.eql(u8, headers_and_body.body_part, "Line 333"));
    expect(i == count);

    var buf: [16]u8 = undefined;
    var buf_len_new = "foo bar baz".len;
    std.mem.copy(u8, buf[0..buf_len_new], "foo bar baz");

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 4, 7, "baz");
    expect(buf_len_new == "foo bar baz".len);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "foo baz baz"));

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 0, 3, "moo");
    expect(buf_len_new == "foo bar baz".len);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "moo baz baz"));

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 8, 11, "bar");
    expect(buf_len_new == "foo bar baz".len);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "moo baz bar"));

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 0, 11, "foo bar baz");
    expect(buf_len_new == "foo bar baz".len);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "foo bar baz"));

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 4, 7, "moo goof");
    expect(buf_len_new == buf.len);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "foo moo goof baz"));

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 4, 8, "");
    expect(buf_len_new == 12);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "foo goof baz"));

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 8, 12, "");
    expect(buf_len_new == 8);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "foo goof"));

    buf_len_new = zag.mem.edit(buf[0..], buf_len_new, 0, 4, "");
    expect(buf_len_new == 4);
    expect(std.mem.eql(u8, buf[0..buf_len_new], "goof"));
}
