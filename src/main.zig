const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{
        .stack_trace_frames = 16,
    }).init;
    // defer _ = debug_allocator.deinit();

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
        try get_output_paths(alloc, input_path);
    defer {
        alloc.free(pp_out);
        alloc.free(asm_out);
        alloc.free(exe);
    }

    { // preprocessor
        var child = std.process.Child.init(
            &.{ "gcc", "-E", "-P", input_path, "-o", pp_out },
            alloc,
        );

        const term = try child.spawnAndWait();
        if (!std.meta.eql(term, .{ .Exited = 0 }))
            return error.PreprocessorFail;
    }

    { // compiler
        const src = try std.fs.cwd().readFileAllocOptions(
            alloc,
            pp_out,
            std.math.maxInt(usize),
            null,
            @alignOf(u8),
            0,
        );
        try std.fs.cwd().deleteFile(pp_out); // cleanup

        var tokenizer = lexer.Tokenizer.init(src);
        while (tokenizer.next()) |token| {
            std.debug.print("{?}: {s}\n", .{ token.tag, src[token.loc.start..token.loc.end] });

            switch (token.tag) {
                .invalid => return error.LexFail,
                else => {},
            }
        }

        if (args.mode == .lex) return;

        // todo
        // take from path `pp_out` output to path `asm_out`
    }

    { // assembler
        var child = std.process.Child.init(
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
    // meant to own the allocation
    const exe = alloc.dupe(u8, get_exe_name(input_path));
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

fn get_exe_name(path: []const u8) []const u8 {
    // copied from std.fs.path.stem with changes
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse
        return path[0..];
    if (index == 0) return path;
    return path[0..index];
}
