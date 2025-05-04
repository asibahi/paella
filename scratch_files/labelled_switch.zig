const std = @import("std");
// var debug_allocator = std.heap.DebugAllocator(.{}).init;

pub fn main() !void {
    const Day = enum { monday, tuesday };
    const S = enum { a, b, c, d };

    const today: Day = .monday;

    loop: switch (S.a) {
        .a => {
            std.debug.print("reached .a\n", .{});
            continue :loop .b;
        },
        .b => {
            std.debug.print("reached .b\n", .{});
            if (today == .monday)
                continue :loop .c
            else
                continue :loop .d;
        },
        .c => std.debug.print("reached .c\n", .{}),
        .d => std.debug.print("reached .d\n", .{}),
    }
}
