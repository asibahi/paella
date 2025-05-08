const std = @import("std");

// struct to intern strings in the compiler
// for IR storing strings/identifiers
//
// same structure could be adapted to include meta data about each identifier such as type and whatnot. this would use a value type instead of `void`.

// code below is copied verbatim
// thanks to InKryption frpm the Zig Discord server
// https://github.com/InKryption

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var interner: StringInterner = .init;
    defer interner.deinit(gpa);

    const foo_id = try interner.getOrPut(gpa, "foo");
    std.debug.print(
        "foo_id: {d} == {?d}, {?s}\n",
        .{
            foo_id,
            interner.getId("foo"),
            interner.getString(foo_id),
        },
    );

    const bar_id = try interner.getOrPut(gpa, "bar");
    std.debug.print(
        "bar_id: {d} == {?d}, {?s}\n",
        .{
            bar_id,
            interner.getId("bar"),
            interner.getString(bar_id),
        },
    );

    std.debug.print("{}\n", .{foo_id == try interner.getOrPut(gpa, "foo")}); // prints true
}

const StringInterner = struct {
    bytes: std.ArrayListUnmanaged(u8),
    map: std.HashMapUnmanaged(
        Id,
        void,
        std.hash_map.StringIndexContext,
        std.hash_map.default_max_load_percentage,
    ),

    pub const init: StringInterner = .{
        .bytes = .empty,
        .map = .empty,
    };

    pub fn deinit(self: *StringInterner, allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
        self.map.deinit(allocator);
    }

    pub const Id = u32;

    pub fn getId(
        self: *const StringInterner,
        string: []const u8,
    ) ?Id {
        return self.map.getKeyAdapted(string, self.hmAdapter());
    }

    pub fn getString(
        self: *const StringInterner,
        id: Id,
    ) ?[:0]const u8 {
        if (!self.map.containsContext(id, self.hmCtx())) return null;
        const slice_sentinel: [:0]const u8 = @ptrCast(self.bytes.items[id..]);
        return std.mem.sliceTo(slice_sentinel, 0);
    }

    pub fn getOrPut(
        self: *StringInterner,
        allocator: std.mem.Allocator,
        string: []const u8,
    ) std.mem.Allocator.Error!Id {
        try self.bytes.ensureUnusedCapacity(allocator, string.len + 1);
        try self.map.ensureUnusedCapacityContext(allocator, 1, self.hmCtx());

        const gop = self.map.getOrPutAssumeCapacityAdapted(string, self.hmAdapter());
        gop.value_ptr.* = {}; // just a reminder that this is void
        if (gop.found_existing) return gop.key_ptr.*;

        if (self.bytes.items.len > std.math.maxInt(Id)) return error.OutOfMemory;
        const new_id: Id = @intCast(self.bytes.items.len);

        self.bytes.appendSliceAssumeCapacity(string);
        self.bytes.appendAssumeCapacity(0);
        gop.key_ptr.* = new_id;
        return new_id;
    }

    fn hmCtx(self: *const StringInterner) std.hash_map.StringIndexContext {
        return .{ .bytes = &self.bytes };
    }

    fn hmAdapter(self: *const StringInterner) std.hash_map.StringIndexAdapter {
        return .{ .bytes = &self.bytes };
    }
};
