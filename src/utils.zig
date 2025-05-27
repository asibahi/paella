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
