const std = @import("std");
usingnamespace @import("../zag.zig");

pub fn Flatree(comptime Payload: type) type {
    return struct {
        all_nodes: std.ArrayList(Node),

        pub const Node = struct {
            parent: ?usize,
            payload: Payload,
        };
        pub const Iterator = struct {
            tree: *const Flatree(Payload),
            parent: ?usize = null,
            i: usize = 0,

            pub fn next(me: *Iterator) ?*const Payload {
                const want_parentless = (me.parent == null);
                while (me.i < me.tree.all_nodes.len) {
                    defer me.i += 1;
                    const is_parentless = (me.tree.all_nodes.items[me.i].parent == null);
                    if (is_parentless == want_parentless)
                        if (is_parentless or me.tree.all_nodes.items[me.i].parent.? == me.parent.?)
                            return &me.tree.all_nodes.items[me.i].payload;
                }
                return null;
            }
        };

        pub fn init(mem: *std.mem.Allocator, initial_capacity: ?usize) !@This() {
            if (initial_capacity) |capacity|
                return @This(){ .all_nodes = try std.ArrayList(Node).initCapacity(mem, capacity) }
            else
                return @This(){ .all_nodes = std.ArrayList(Node).init(mem) };
        }

        pub fn deinit(me: *@This()) void {
            me.all_nodes.deinit();
        }

        pub fn get(me: *const @This(), node_id: usize) *Payload {
            return &me.all_nodes.items[node_id].payload;
        }

        pub fn hasSubNodes(me: *const @This(), parent: ?usize) bool {
            if (parent) |idx| {
                std.debug.assert(idx < me.all_nodes.len);
                for (me.all_nodes.items[0..me.all_nodes.len]) |*node|
                    if (node.parent) |node_parent_idx|
                        if (node_parent_idx == idx)
                            return true;
            } else for (me.all_nodes.items[0..me.all_nodes.len]) |*node|
                if (node.parent == null)
                    return true;
            return false;
        }

        pub fn numSubNodes(me: *const @This(), parent: ?usize, max: usize) usize {
            var ret: usize = 0;
            if (parent) |idx| {
                std.debug.assert(idx < me.all_nodes.len);
                for (me.all_nodes.items[0..me.all_nodes.len]) |*node|
                    if (node.parent) |node_parent_idx|
                        if (node_parent_idx == idx) {
                            ret += 1;
                            if (ret == max)
                                return ret;
                        };
            } else for (me.all_nodes.items[0..me.all_nodes.len]) |*node|
                if (node.parent == null) {
                    ret += 1;
                    if (ret == max)
                        return ret;
                };
            return ret;
        }

        pub fn subNodesOf(me: *const @This(), parent: ?usize) ?Iterator {
            if (parent) |idx| {
                std.debug.assert(idx < me.all_nodes.len);
                return Iterator{ .tree = me, .parent = idx };
            }
            return Iterator{ .tree = me };
        }

        fn indexOfPayload(me: *const @This(), needle: *const Payload) ?usize {
            for (me.all_nodes.items[0..me.all_nodes.len]) |*node, i|
                if (&node.payload == needle)
                    return i;
            return null;
        }

        pub fn find(me: *const @This(), where: fn (*Payload) bool) ?*Payload {
            for (me.all_nodes.items[0..me.all_nodes.len]) |*node|
                if (where(&node.payload))
                    return &node.payload;
            return null;
        }

        pub fn haveAny(me: *const @This(), mem: *std.mem.Allocator, check: fn (*const Payload) bool, start_from: ?usize) !bool {
            var stack = try std.ArrayList(usize).initCapacity(mem, me.all_nodes.len);
            defer stack.deinit();

            if (start_from) |idx| {
                std.debug.assert(idx < me.all_nodes.len);
                try stack.append(idx);
            } else { // multiple start-froms: all root-level / parent-less items
                var i: usize = me.all_nodes.len;
                while (i > 0) {
                    i -= 1;
                    if (me.all_nodes.items[i].parent == null)
                        try stack.append(i);
                }
            }

            while (stack.popOrNull()) |idx| {
                if (check(&me.all_nodes.items[idx].payload))
                    return true;
                var i = me.all_nodes.len;
                while (i > 0) {
                    i -= 1;
                    if ((me.all_nodes.items[i].parent orelse continue) == idx)
                        try stack.append(i);
                }
            }
            return false;
        }

        const OrderedList = []struct {
            depth: usize,
            node_id: usize,
            value: *Payload,
            parent: ?usize,
        };

        pub fn toOrderedList(me: *const @This(), mem: *std.mem.Allocator, start_from: ?usize) !OrderedList {
            var ret = try std.ArrayList(@typeInfo(OrderedList).Pointer.child).initCapacity(mem, me.all_nodes.len);

            const StackItem = struct { idx: usize, depth: usize };
            var stack = try std.ArrayList(StackItem).initCapacity(mem, me.all_nodes.len);
            defer stack.deinit();

            if (start_from) |idx| {
                std.debug.assert(idx < me.all_nodes.len);
                try stack.append(StackItem{ .depth = 0, .idx = idx });
            } else { // multiple start-froms: all root-level / parent-less items
                var i: usize = me.all_nodes.len;
                while (i > 0) {
                    i -= 1;
                    if (me.all_nodes.items[i].parent == null)
                        try stack.append(StackItem{ .idx = i, .depth = 0 });
                }
            }

            while (stack.popOrNull()) |stack_item| {
                var i = me.all_nodes.len;
                while (i > 0) {
                    i -= 1;
                    if ((me.all_nodes.items[i].parent orelse continue) == stack_item.idx)
                        try stack.append(StackItem{ .idx = i, .depth = 1 + stack_item.depth });
                }
                try ret.append(.{
                    .depth = stack_item.depth,
                    .node_id = stack_item.idx,
                    .value = &me.all_nodes.items[stack_item.idx].payload,
                    .parent = me.all_nodes.items[stack_item.idx].parent,
                });
            }

            return ret.toOwnedSlice();
        }

        pub fn add(me: *@This(), add_this: Payload, to_parent: ?usize) !usize {
            if (to_parent) |parent|
                std.debug.assert(parent < me.all_nodes.len);
            try me.all_nodes.append(.{ .parent = to_parent, .payload = add_this });
            return me.all_nodes.len - 1;
        }

        pub fn remove(me: *@This(), mem: *std.mem.Allocator, remove_this: usize) !void {
            var removals = try std.ArrayList(usize).initCapacity(mem, 8);
            defer removals.deinit();

            var stack = try std.ArrayList(usize).initCapacity(mem, 8);
            defer stack.deinit();
            std.debug.assert(remove_this < me.all_nodes.len);
            try stack.append(remove_this);
            while (stack.popOrNull()) |idx| {
                try removals.append(idx);
                for (me.all_nodes.items[0..me.all_nodes.len]) |*node, i|
                    if (node.parent) |node_parent_idx|
                        if (node_parent_idx == idx)
                            try stack.append(i);
            }

            var i: usize = removals.len;
            while (i > 0) {
                i -= 1;
                const remove_idx = removals.items[i];
                for (me.all_nodes.items[0..me.all_nodes.len]) |_, idx| {
                    if (me.all_nodes.items[idx].parent) |parent| {
                        std.debug.assert(parent != remove_idx);
                        if (parent > remove_idx)
                            me.all_nodes.items[idx].parent = parent - 1;
                    }
                }
                _ = me.all_nodes.orderedRemove(remove_idx);
            }
        }

        pub fn moveSubNodesToNewParent(me: *const @This(), old_parent: ?usize, new_parent: ?usize) void {
            if ((old_parent == null and new_parent == null) or
                ((old_parent != null and new_parent != null and old_parent.? == new_parent.?)))
                return;
            for (me.all_nodes.items[0..me.all_nodes.len]) |*node| {
                if (node.parent) |node_parent_idx| {
                    if (node_parent_idx == (old_parent orelse continue))
                        node.parent = new_parent;
                } else if (old_parent == null)
                    node.parent = new_parent;
            }
        }
    };
}
