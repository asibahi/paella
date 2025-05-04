const std = @import("std");
var debug_allocator = std.heap.DebugAllocator(.{}).init;


// ast rep article: https://keleshev.com/abstract-syntax-tree-an-example-in-c/
//


pub fn main() !void {
    const gpa = debug_allocator.allocator();
    defer _ = debug_allocator.deinit();

    var arena_allocator = std.heap.ArenaAllocator.init(gpa);
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();

    const lhs = try arena.create(Expr);
    const rhs = try arena.create(Expr);
    const add = try arena.create(Expr);

    lhs.* = .{ .number = 64 };
    rhs.* = .{ .number = 129100 };
    add.* = .{ .add = .{ lhs, rhs } };

    std.debug.print("{?}\n", .{add.*});
}

const Expr = union(enum) {
    number: u64,
    add: struct { *Expr, *Expr },
    sub: struct { *Expr, *Expr },

};

const Stmt = union(enum) {
    return_: ?*Expr,
};
