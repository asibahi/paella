const std = @import("std");
const bi = @import("builtin");
const utils = @import("utils.zig");

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ir = @import("ir_gen.zig");
const asm_gen = @import("asm_gen.zig");
const sema = @import("sema.zig");

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{
        .stack_trace_frames = 16,
    }).init;
    defer _ = debug_allocator.deinit();

    const gpa = debug_allocator.allocator();

    const args = try parse_args();
    try run(gpa, args);
}

fn run(
    gpa: std.mem.Allocator,
    args: Args,
) !void {
    const input_path = args.path;
    const pp_out, const asm_out, const obj, const exe =
        try get_output_paths(gpa, input_path);
    defer {
        gpa.free(pp_out);
        gpa.free(asm_out);
        gpa.free(obj);
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
                if (bi.mode == .Debug)
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

        var prgm_ir = parse: {
            var arena_allocator = std.heap.ArenaAllocator.init(gpa);
            const arena = arena_allocator.allocator();
            defer arena_allocator.deinit();

            var ast = try parser.parse_prgm(arena, &tokenizer);

            if (args.mode == .parse) {
                if (bi.mode == .Debug)
                    std.debug.print("{}\n", .{ast});
                return;
            }

            var type_map = try sema.resolve_prgm(gpa, &strings, &ast);

            if (args.mode == .validate) {
                if (bi.mode == .Debug)
                    std.debug.print("{}\n", .{ast});
                return;
            }

            break :parse try ir.prgm_emit_ir(gpa, &strings, &type_map, &ast);
        };

        { // optimization pass
            try prgm_ir.optimize(gpa, args.optimizations);
        }

        var prgm_asm = asm_gen: {
            defer prgm_ir.deinit(gpa);

            if (args.mode == .tacky) {
                if (bi.mode == .Debug)
                    std.debug.print("{any}\n", .{prgm_ir});

                prgm_ir.type_map.deinit(gpa);
                return;
            }

            break :asm_gen try asm_gen.prgm_to_asm(gpa, prgm_ir);
        };
        defer prgm_asm.deinit(gpa);
        try prgm_asm.fixup(gpa);

        if (args.mode == .codegen) {
            if (bi.mode == .Debug)
                std.debug.print("{}\n", .{prgm_asm});
            return;
        }

        { // create assembly file
            if (args.mode == .assembly) {
                std.debug.print("{gen}\n", .{prgm_asm});
                return;
            } else {
                const asm_file = try std.fs.cwd().createFile(asm_out, .{});
                defer asm_file.close();
                var asm_writer = asm_file.writer();

                try asm_writer.print("{gen}\n", .{prgm_asm});
            }
        }

        if (args.mode == .output_assembly) return;
    }

    { // assembler
        var child = std.process.Child.init(
            if (args.c_flag)
                &.{ "gcc", "-c", asm_out, "-o", obj }
            else
                &.{ "gcc", asm_out, "-o", exe },
            gpa,
        );

        const term = try child.spawnAndWait();
        if (!std.meta.eql(term, .{ .Exited = 0 }))
            return error.AssemblerFail;

        try std.fs.cwd().deleteFile(asm_out); // cleanup
    }
}

const Args = struct {
    path: [:0]const u8,
    mode: Mode,
    c_flag: bool,
    optimizations: std.EnumSet(Optimization),
};

const Mode = enum {
    lex,
    parse,
    validate,
    tacky,
    codegen,
    compile, // default
    assembly, // unused by test script - useful for debugging
    output_assembly, // -S : generate an assembly file
};

const Optimization = @import("ir_opt.zig").Optimization;

fn parse_args() !Args {
    var args = std.process.args();
    _ = args.skip();

    var path: ?[:0]const u8 = null;
    var mode: Mode = .compile;
    var c_flag = false;
    var optimizations: std.EnumSet(Optimization) = .initEmpty();

    while (args.next()) |arg| {
        if (arg[0] == '-') {
            if (arg[1] == 'c')
                c_flag = true
            else if (arg[1] == 'S' or arg[1] == 's')
                mode = .output_assembly
            else if (std.meta.stringToEnum(Mode, arg[2..])) |m|
                mode = m
            else if (std.meta.stringToEnum(Optimization, arg[2..])) |opt|
                optimizations.insert(opt)
            else if (std.mem.eql(u8, "optimize", arg[2..]))
                optimizations = .initFull()
            else
                return error.UnrecognizedFlag;
        } else if (path == null)
            path = arg
        else
            return error.PathDuplicated;
    }

    return .{
        .path = path orelse return error.PathNotFound,
        .mode = mode,
        .c_flag = c_flag,
        .optimizations = optimizations,
    };
}

fn get_output_paths(
    alloc: std.mem.Allocator,
    input_path: []const u8,
) !struct {
    []const u8,
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

    const obj = try std.mem.join(
        alloc,
        ".",
        &.{ exe, "o" },
    );
    errdefer alloc.free(obj);

    const @"asm" = try std.mem.join(
        alloc,
        ".",
        &.{ exe, "s" },
    );

    return .{ pp, @"asm", obj, exe };
}

fn strip_extension(path: []const u8) []const u8 {
    // copied from std.fs.path.stem with changes
    const index = std.mem.lastIndexOfScalar(u8, path, '.') orelse
        return path;
    if (index == 0) return path;
    return path[0..index];
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
