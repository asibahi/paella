const std = @import("std");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{
        .stack_trace_frames = 16,
    }).init;
    defer _ = debug_allocator.deinit();

    const gpa = debug_allocator.allocator();

    const args = try parse_args();
    try run(gpa, args);
}

pub fn run(
    alloc: std.mem.Allocator,
    args: Args,
) !void {
    const input_path = args.path;
    const pp_out, const asm_out, const exe =
        get_output_paths(alloc, input_path);
    defer {
        alloc.free(pp_out);
        alloc.free(asm_out);
        alloc.free(exe);
    }

    { // preprocessor
        const child = std.process.Child.init(
            &.{ "gcc", "-E", "-P", input_path, "-o", pp_out },
            alloc,
        );

        const term = try child.spawnAndWait();
        if (!std.meta.eql(term, .{ .Exited = 0 }))
            return error.PreprocessorFail;
    }

    { // compiler
        _ = args.mode;
        // mode controls compilation here

        // todo
        // take from path `pp_out` output to path `asm_out`
    }

    { // assembler
        const child = std.process.Child.init(
            &.{ "gcc", asm_out, "-o", exe },
            alloc,
        );

        const term = try child.spawnAndWait();
        if (!std.meta.eql(term, .{ .Exited = 0 }))
            return error.AssemblerFail;

        try std.fs.cwd().deleteFile(asm_out); // cleanup
    }
}

pub const Args = struct {
    path: [:0]const u8,
    mode: Mode,
};
pub const Mode = enum {
    lex,
    parse,
    codegen,
    compile, // default
    assembly, // unused by test script - useful for debugging
};

pub fn parse_args() !Args {
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

fn get_output_paths(
    alloc: std.mem.Allocator,
    input_path: []const u8,
) !struct {
    []const u8,
    []const u8,
    []const u8,
} {
    const exe = try std.fs.path.join(
        alloc,
        &.{
            std.fs.path.dirname(input_path) orelse "",
            std.fs.path.stem(input_path),
        },
    );
    errdefer alloc.free(exe);

    const pp = try std.mem.join(
        alloc,
        ".",
        &.{ exe, "i" },
    );
    errdefer alloc.free(pp);

    const @"asm" = try std.mem.join(
        alloc,
        ".",
        &.{ exe, "s" },
    );

    return .{ pp, @"asm", exe };
}
