//! `StringInterner.zig`, but using `ArrayHashMap` instead of `HashMap`.
//!
//! This specific implementation has a bit more memory overhead (16 bytes per item instead of 13),
//! but is (probably) faster. I could instead have given it similar performance, and had less memory
//! overhead (12 bytes per item instead of 13).
//!
//! Usually, at least in simple cases, `ArrayHashMap` will have more memory overhead than `HashMap`;
//! that's its main weakness. But in this case, it's able to be better, because we can calculate
//! your "metadata" value based on the index of an element in the map.

// https://zigbin.io/f24912
// StringInterner provided kindly by mlugg on zig discord
// all text (other than this comment), written by mlugg

string_bytes: std.ArrayListUnmanaged(u8),
/// Key is the index of the string in `string_bytes`. I've used the type-safe enum wrapper here,
/// because we have to implement the adapter ourselves anyway (std doesn't have a string index
/// adapter for `ArrayHashMap`), so we may as well be type-safe!
/// Metadata is implicit from the index of an entry in the table.
/// Accessed through `Adapter`.
string_table: std.ArrayHashMapUnmanaged(
    String,
    void,
    // This is the context, but I've written this so that the context should never be used, so I'm
    // just passing `void`; we'll get a compile error if it's ever used. The reason it's never used
    // is because of the next argument...
    void,
    // This is whether the computed hash value should be stored. I'm passing `true`, because since
    // strings can be arbitrarily big, `hash` and `eql` are somewhat expensive operations. It adds
    // 4 bytes of overhead per element, taking it up to 16 bytes per element. Personally I'd accept
    // that tradeoff, to minimize expensive `hash`/`eql` calls.
    //
    // If memory usage were a problem, you could pass `false` here; you'd save those 4 bytes, but in
    // exchange would have to provide a valid `Context` above. The performance characteristics would
    // then be about the same as a normal `HashMapUnmanaged` (since that never stores the hashes).
    true,
),

pub const empty: StringInterner = .{
    .string_bytes = .empty,
    .string_table = .empty,
};

const Adapter = struct {
    si: *StringInterner,

    /// This tells the `ArrayHashMap` how our "pseudo keys" (which are `[]const u8`) should be
    /// hashed. Remember that it'll store this hash permanently, so it doesn't need to know how
    /// to hash the stored `String` keys!
    pub fn hash(ctx: Adapter, str: []const u8) u32 {
        _ = ctx; // we don't need the string data for this
        return @truncate(std.hash.Wyhash.hash(0, str));
    }

    /// This tells the `ArrayHashMap` how to compare our "pseudo key" (`[]const u8`) to a "real
    /// key", which is the stored `String`.
    pub fn eql(ctx: Adapter, a_slice: []const u8, b_str: String, b_index: usize) bool {
        // Every element in an `ArrayHashMap` has an index in the range 0 <= i < len; that's what
        // `b_index` is here. We aren't using that index for anything interesting in this case; we
        // only care about `b_str`.
        _ = b_index;
        const b_slice = b_str.get(ctx.si);
        return std.mem.eql(u8, a_slice, b_slice);
    }
};

pub fn deinit(si: *StringInterner, gpa: Allocator) void {
    si.string_bytes.deinit(gpa);
    si.string_table.deinit(gpa);
}

/// This is exactly the same as the `HashMap` version.
pub const String = enum(u32) {
    _,
    pub fn get(s: String, si: *StringInterner) [:0]u8 {
        const overlong_slice = si.string_bytes.items[@intFromEnum(s)..];
        const len = std.mem.indexOfScalar(u8, overlong_slice, 0).?;
        return overlong_slice[0..len :0];
    }
};

pub fn get(si: *StringInterner, gpa: Allocator, string: []const u8) Allocator.Error!struct {
    string: String,
    metadata: i64,
} {
    // Make sure we'll have space for the string plus its null terminator.
    try si.string_bytes.ensureUnusedCapacity(gpa, string.len + 1);
    // Same idea as before, but we don't need to pass a context here, because, as we discussed
    // above, the hashes are stored in memory and don't need to be recomputed.
    try si.string_table.ensureUnusedCapacity(gpa, 1);

    errdefer comptime unreachable;

    // Use our custom adapter!
    const adapter: Adapter = .{ .si = si };
    const gop = si.string_table.getOrPutAssumeCapacityAdapted(string, adapter);
    // Before returning, calculate the metadata from the entry's index in the string table. (We
    // might be about to *add* this string to `string_bytes`, but that's fine, it doesn't affect
    // this computation!)
    const metadata: i64 = -4 - @as(i64, @intCast(gop.index)) * 4;

    if (gop.found_existing) {
        return .{
            .string = gop.key_ptr.*,
            .metadata = metadata,
        };
    }

    // The string doesn't exist, so we'll add it to `string_bytes`, and set up this new entry in
    // `string_table` to point to that data. That means our `Adapter` will understand that the
    // "key" (a `String`) actually points to the string data we're about to append.

    // The string will be added to the end of `string_bytes`, so its current len is the start index.
    const new_string: String = @enumFromInt(si.string_bytes.items.len);
    si.string_bytes.appendSliceAssumeCapacity(string);
    si.string_bytes.appendAssumeCapacity(0); // null terminator

    gop.key_ptr.* = new_string;
    // We don't have a value to set, since the metadata is implicit; `gop.value_ptr` points to `void`!

    return .{
        .string = new_string,
        .metadata = metadata,
    };
}

test StringInterner {
    const gpa = std.testing.allocator;

    var si: StringInterner = .empty;
    defer si.deinit(gpa);

    const hello = try si.get(gpa, "hello");
    const world = try si.get(gpa, "world");

    const hello_1 = try si.get(gpa, "hello");
    const world_1 = try si.get(gpa, "world");

    const another_thing = try si.get(gpa, "another thing!");

    const hello_2 = try si.get(gpa, "hello");
    const world_2 = try si.get(gpa, "world");

    try expect(std.meta.eql(hello, hello_1));
    try expect(std.meta.eql(hello, hello_2));

    try expect(std.meta.eql(world, world_1));
    try expect(std.meta.eql(world, world_2));

    try expect(hello.metadata == -4);
    try expect(world.metadata == -8);
    try expect(another_thing.metadata == -12);

    try expectEqualStrings("hello", hello.string.get(&si));
    try expectEqualStrings("world", world.string.get(&si));
    try expectEqualStrings("another thing!", another_thing.string.get(&si));
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const StringInterner = @This();
