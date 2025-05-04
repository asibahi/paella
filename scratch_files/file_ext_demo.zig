const std = @import("std");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();

    const alloc = debug_allocator.allocator();

    const path = "foo/bar.txt";
    const stem = try std.fs.path.join(
        alloc,
        &.{
            std.fs.path.dirname(path) orelse "",
            std.fs.path.stem(path),
        },
    );
    defer alloc.free(stem);

    const new_path = try std.mem.join(
        alloc,
        ".",
        &.{
            stem,
            "TXT",
        },
    );
    defer alloc.free(new_path);

    std.debug.assert(std.mem.eql(u8, new_path, "foo/bar.TXT"));

    std.debug.print("{s}\n", .{new_path});
}
