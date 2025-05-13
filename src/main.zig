const std = @import("std");
const utils = @import("utils.zig");

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ir = @import("ir_gen.zig");
// const asm_gen = @import("asm_gen.zig");

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
    gpa: std.mem.Allocator,
    args: Args,
) !void {
    const input_path = args.path;
    const pp_out, const asm_out, const exe =
        try get_output_paths(gpa, input_path);
    defer {
        gpa.free(pp_out);
        gpa.free(asm_out);
        gpa.free(exe);
    }

    { // preprocessor
        var child = std.process.Child.init(
            &.{ "gcc", "-E", "-P", input_path, "-o", pp_out },
            gpa,
        );

        const term = try child.spawnAndWait();
        if (!std.meta.eql(term, .{ .Exited = 0 }))
            return error.PreprocessorFail;
    }

    { // compiler
        const src = try std.fs.cwd().readFileAllocOptions(
            gpa,
            pp_out,
            std.math.maxInt(usize),
            null,
            @alignOf(u8),
            0,
        );
        try std.fs.cwd().deleteFile(pp_out); // cleanup
        defer gpa.free(src);

        var tokenizer = lexer.Tokenizer.init(src);

        if (args.mode == .lex) {
            while (tokenizer.next()) |token| {
                if (@import("builtin").mode == .Debug)
                    std.debug.print("{s:<16}: {s}\n", .{
                        @tagName(token.tag),
                        src[token.loc.start..token.loc.end],
                    });

                switch (token.tag) {
                    .invalid => return error.LexFail,
                    else => {},
                }
            }
            return;
        }

        var strings = utils.StringInterner.empty;
        defer strings.deinit(gpa);

        var prgm_ir = arena: {
            var arena_allocator = std.heap.ArenaAllocator.init(gpa);
            const arena = arena_allocator.allocator();
            defer arena_allocator.deinit();

            const ast = try parser.parse_prgm(arena, &tokenizer);

            if (args.mode == .parse) {
                std.debug.print("{}\n", .{ast});
                return;
            }

            break :arena try ir.prgm_emit_it(gpa, &strings, ast);
        };
        defer prgm_ir.deinit(gpa);

        if (args.mode == .tacky) {
            std.debug.print("{any}\n", .{prgm_ir});
            return;
        }

        // if (args.mode == .codegen) {
        //     std.debug.print("{}\n", .{prgm});
        //     return;
        // }

        // { // create assembly file
        //     const asm_file = try std.fs.cwd().createFile(asm_out, .{});
        //     defer asm_file.close();
        //     var asm_writer = asm_file.writer();

        //     try asm_writer.print("{gen}\n", .{prgm});

        //     if (args.mode == .assembly) return;
        // }
    }

    // { // assembler
    //     var child = std.process.Child.init(
    //         &.{ "gcc", asm_out, "-o", exe },
    //         gpa,
    //     );

    //     const term = try child.spawnAndWait();
    //     if (!std.meta.eql(term, .{ .Exited = 0 }))
    //         return error.AssemblerFail;

    //     try std.fs.cwd().deleteFile(asm_out); // cleanup
    // }
}

pub const Args = struct {
    path: [:0]const u8,
    mode: Mode,
};
pub const Mode = enum {
    lex,
    parse,
    tacky,
    codegen,
    compile, // default
    assembly, // unused by test script - useful for debugging
};

pub fn parse_args() !Args {
    var args = std.process.args();
    _ = args.skip();

    var path: ?[:0]const u8 = null;
    var mode: Mode = .compile;

    while (args.next()) |arg| {
        if (arg[0] == '-') {
            mode = std.meta.stringToEnum(Mode, arg[2..]) orelse
                return error.UnrecognizedFlag;
        } else if (path == null) {
            path = arg;
        } else {
            return error.PathDuplicated;
        }
    }

    return .{
        .path = path orelse return error.PathNotFound,
        .mode = mode,
    };
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
    const exe = try alloc.dupe(u8, strip_extension(input_path));
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

fn strip_extension(path: []const u8) []const u8 {
    // copied from std.fs.path.stem with changes
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse
        return path;
    if (index == 0) return path;
    return path[0..index];
}
