const std = @import("std");

pub fn create(T: type, alloc: std.mem.Allocator, value: T) !*T {
    const ret = try alloc.create(T);
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
        return self.map.getKeyAdapted(string, self.adapter());
    }

    pub fn get_string(
        self: *const StringInterner,
        id: Idx,
    ) ?[:0]const u8 {
        if (!self.map.containsContext(id, self.ctx()))
            return null;

        const st: [:0]const u8 = @ptrCast(self.bytes.items[id..]);
        return std.mem.sliceTo(st, 0);
    }

    pub fn get_or_put(
        self: *StringInterner,
        allocator: std.mem.Allocator,
        string: []const u8,
    ) std.mem.Allocator.Error!GetOrPutResult {
        try self.bytes.ensureUnusedCapacity(allocator, string.len + 1);
        try self.map.ensureUnusedCapacityContext(allocator, 1, self.ctx());

        const gop = self.map.getOrPutAssumeCapacityAdapted(string, self.adapter());
        gop.value_ptr.* = {}; // just a reminder that this is void

        if (gop.found_existing)
            return .init(self, gop.key_ptr.*);

        if (self.bytes.items.len > std.math.maxInt(Idx))
            return error.OutOfMemory;
        const new_id: Idx = @intCast(self.bytes.items.len);

        self.bytes.appendSliceAssumeCapacity(string);
        self.bytes.appendAssumeCapacity(0);
        gop.key_ptr.* = new_id;

        return .init(self, new_id);
    }

    fn ctx(self: *const StringInterner) std.hash_map.StringIndexContext {
        return .{ .bytes = &self.bytes };
    }

    fn adapter(self: *const StringInterner) std.hash_map.StringIndexAdapter {
        return .{ .bytes = &self.bytes };
    }
};
