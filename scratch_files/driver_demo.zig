const std = @import("std");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_allocator.deinit();

    const gpa = debug_allocator.allocator();

    const args = try parse_args();
    std.debug.print("{s} - {}\n", .{ args.path, args.mode });

    var child = std.process.Child.init(
        &.{ "echo", "bar", args.path },
        gpa,
    );

    const term = try child.spawnAndWait();
    if (!std.meta.eql(term, .{ .Exited = 0 }))
        return error.SubProcessFail;

    std.debug.print("{?}\n", .{term});
}

const Args = struct {
    path: [:0]const u8,
    mode: Mode,
};
const Mode = enum { lex, parse, codegen, compile };

fn parse_args() !Args {
    var args = std.process.args();
    _ = args.skip();
    const path = args.next() orelse
        return error.PathNotFound;

    const mode: Mode = if (args.next()) |arg|
        std.meta.stringToEnum(Mode, arg[2..]) orelse
            return error.UnrecognizedFlag
    else
        .compile;

    return .{ .path = path, .mode = mode };
}
