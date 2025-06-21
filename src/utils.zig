const std = @import("std");

pub fn create(
    alloc: std.mem.Allocator,
    value: anytype,
) std.mem.Allocator.Error!*@TypeOf(value) {
    const ret = try alloc.create(@TypeOf(value));
    ret.* = value;
    return ret;
}

pub const StringInterner = struct {
    bytes: std.ArrayListUnmanaged(u8),
    map: std.HashMapUnmanaged(
        u32,
        void,
        std.hash_map.StringIndexContext,
        std.hash_map.default_max_load_percentage,
    ),

    pub const empty: StringInterner = .{
        .bytes = .empty,
        .map = .empty,
    };

    pub fn deinit(self: *StringInterner, allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
        self.map.deinit(allocator);
    }

    pub const Idx = struct {
        real_idx: u32,
        strings: *const StringInterner,
        pub fn format(
            self: @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("{s}", .{self.strings.get_string(self).?});
        }
    };

    pub fn get_string(
        self: *const StringInterner,
        idx: Idx,
    ) ?[:0]const u8 {
        const id_int = idx.real_idx;
        if (!self.map.containsContext(id_int, .{ .bytes = &self.bytes }))
            return null;

        const st: [:0]const u8 = @ptrCast(self.bytes.items[id_int..]);
        return std.mem.sliceTo(st, 0);
    }

    pub fn get_or_put(
        self: *StringInterner,
        gpa: std.mem.Allocator,
        string: []const u8,
    ) std.mem.Allocator.Error!Idx {
        try self.bytes.ensureUnusedCapacity(gpa, string.len + 1);
        try self.map.ensureUnusedCapacityContext(gpa, 1, .{ .bytes = &self.bytes });

        const adapter: std.hash_map.StringIndexAdapter = .{ .bytes = &self.bytes };
        const gop = self.map.getOrPutAssumeCapacityAdapted(string, adapter);
        gop.value_ptr.* = {}; // just a reminder that this is void

        if (gop.found_existing)
            return .{ .real_idx = gop.key_ptr.*, .strings = self };

        const new_id: u32 = @intCast(self.bytes.items.len);

        self.bytes.appendSliceAssumeCapacity(string);
        self.bytes.appendAssumeCapacity(0);
        gop.key_ptr.* = new_id;

        return .{ .real_idx = new_id, .strings = self };
    }

    pub fn make_temporary(
        self: *StringInterner,
        gpa: std.mem.Allocator,
        prefix: []const u8,
    ) !Idx {
        // zig static variables
        const static = struct {
            var counter: usize = 0;
        };

        var buf: [64]u8 = undefined;
        const name_buf = try std.fmt.bufPrint(
            &buf,
            "{s}.{}",
            .{ (if (prefix.len == 0) "tmp" else prefix), static.counter },
        );

        const name = try self.get_or_put(gpa, name_buf);
        static.counter += 1;

        return name;
    }
};

// ============ CFG ============

pub const GenericInstr = union(enum) {
    ret,
    jmp: StringInterner.Idx,
    cond_jmp: StringInterner.Idx,
    label: StringInterner.Idx,
    other,
};

pub fn ControlFlowGraph(Instr: type) type {
    return struct {
        const Node = union(enum) {
            entry,
            exit,
            tombstone,
            basic_block: std.ArrayListUnmanaged(Instr),
        };

        nodes: std.ArrayListUnmanaged(Node),
        edges: std.ArrayListUnmanaged(struct { usize, usize }),

        pub fn init(
            gpa: std.mem.Allocator,
            instrs: std.ArrayListUnmanaged(Instr),
        ) !@This() {
            var nodes: std.ArrayListUnmanaged(Node) = .empty;
            try nodes.append(gpa, .entry);

            { // partition basic blocks
                var current_node: Node = .{ .basic_block = .empty };
                for (instrs.items) |instr| switch (instr.to_generic()) {
                    .label => {
                        if (current_node.basic_block.items.len > 0)
                            try nodes.append(gpa, current_node);

                        current_node = .{ .basic_block = .empty };
                        try current_node.basic_block.append(gpa, instr);
                    },
                    .ret, .jmp, .cond_jmp => {
                        try current_node.basic_block.append(gpa, instr);
                        try nodes.append(gpa, current_node);

                        current_node = .{ .basic_block = .empty };
                    },
                    .other => try current_node.basic_block.append(gpa, instr),
                };
                try nodes.append(gpa, .exit);
            }

            var edges: std.ArrayListUnmanaged(struct { usize, usize }) = .empty;

            { // adding edges
                // entry to block 1.
                try edges.append(gpa, .{ 0, 1 });
                const exit_idx = nodes.items.len - 1;

                for (nodes.items, 0..) |node, idx| if (node == .basic_block) {
                    const gen = node.basic_block.getLast().to_generic();
                    switch (gen) {
                        .ret => try edges.append(gpa, .{ idx, exit_idx }),
                        .other, .label => try edges.append(gpa, .{ idx, idx + 1 }),
                        .jmp, .cond_jmp => |l| {
                            const target_idx = for (nodes.items, 0..) |n, i| {
                                if (n == .basic_block) {
                                    const fst = n.basic_block.items[0].to_generic();
                                    if (fst == .label and fst.label.real_idx == l.real_idx)
                                        break i;
                                }
                            } else unreachable;

                            try edges.append(gpa, .{ idx, target_idx });
                            if (gen == .cond_jmp)
                                try edges.append(gpa, .{ idx, idx + 1 });
                        },
                    }
                };
            }

            return .{
                .nodes = nodes,
                .edges = edges,
            };
        }

        pub fn deinit(
            self: *@This(),
            gpa: std.mem.Allocator,
        ) void {
            for (self.nodes.items) |*node| switch (node.*) {
                .basic_block => |*l| l.deinit(gpa),
                else => {},
            };
            self.nodes.deinit(gpa);
            self.edges.deinit(gpa);
        }

        pub fn delete_node(
            self: *@This(),
            gpa: std.mem.Allocator,
            index: usize,
        ) void {
            std.debug.assert(self.nodes.items[index] == .basic_block);

            if (@hasDecl(Instr, "deinit"))
                for (self.nodes.items[index].basic_block.items) |*instr|
                    instr.deinit(gpa);

            self.nodes.items[index].basic_block.deinit(gpa);
            self.nodes.items[index] = .tombstone;

            var idx = self.edges.items.len;
            while (idx > 0) : (idx -= 1) {
                const edge = self.edges.items[idx - 1];
                if (edge.@"0" == index or edge.@"1" == index)
                    _ = self.edges.swapRemove(idx - 1);
            }
        }

        pub fn concat(
            self: @This(),
            gpa: std.mem.Allocator,
            instrs: *std.ArrayListUnmanaged(Instr),
        ) !void {
            var out: std.ArrayListUnmanaged(Instr) = .empty;
            defer {
                std.mem.swap(
                    std.ArrayListUnmanaged(Instr),
                    &out,
                    instrs,
                );
                out.deinit(gpa);
            }

            for (self.nodes.items) |node| if (node == .basic_block)
                try out.appendSlice(gpa, node.basic_block.items);
        }

        // todo the rest
        //
    };
}
