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
        Idx,
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

    pub const Idx = u32;
    pub const GetOrPutResult = struct {
        idx: Idx,
        string: [:0]const u8,
        // value: void,

        fn init(self: *const StringInterner, idx: Idx) @This() {
            return .{
                .idx = idx,
                .string = get_string(self, idx).?,
            };
        }
    };

    pub fn get_idx(
        self: *const StringInterner,
        string: []const u8,
    ) ?Idx {
        return self.map.getKeyAdapted(string, .{ .bytes = &self.bytes });
    }

    pub fn get_string(
        self: *const StringInterner,
        id: Idx,
    ) ?[:0]const u8 {
        if (!self.map.containsContext(id, .{ .bytes = &self.bytes }))
            return null;

        const st: [:0]const u8 = @ptrCast(self.bytes.items[id..]);
        return std.mem.sliceTo(st, 0);
    }

    pub fn get_or_put(
        self: *StringInterner,
        gpa: std.mem.Allocator,
        string: []const u8,
    ) std.mem.Allocator.Error!GetOrPutResult {
        try self.bytes.ensureUnusedCapacity(gpa, string.len + 1);
        try self.map.ensureUnusedCapacityContext(gpa, 1, .{ .bytes = &self.bytes });

        const adapter: std.hash_map.StringIndexAdapter = .{ .bytes = &self.bytes };
        const gop = self.map.getOrPutAssumeCapacityAdapted(string, adapter);
        gop.value_ptr.* = {}; // just a reminder that this is void

        if (gop.found_existing)
            return .init(self, gop.key_ptr.*);

        const new_id: Idx = @intCast(self.bytes.items.len);

        self.bytes.appendSliceAssumeCapacity(string);
        self.bytes.appendAssumeCapacity(0);
        gop.key_ptr.* = new_id;

        return .init(self, new_id);
    }

    pub fn make_temporary(
        self: *StringInterner,
        gpa: std.mem.Allocator,
        prefix: []const u8,
    ) ![:0]const u8 {
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

        return name.string;
    }
};
