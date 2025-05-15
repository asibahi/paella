const std = @import("std");

const ir = @import("ir.zig");
const assembly = @import("assembly.zig");

const utils = @import("utils.zig");

pub fn prgm_to_asm(
    alloc: std.mem.Allocator,
    prgm: ir.Prgm,
) !assembly.Prgm {
    const func_def = try utils.create(
        assembly.FuncDef,
        alloc,
        try func_def_to_asm(alloc, prgm.func_def.*),
    );

    return .{ .func_def = func_def };
}

fn func_def_to_asm(
    alloc: std.mem.Allocator,
    func_def: ir.FuncDef,
) !assembly.FuncDef {
    var arena_allocator = std.heap.ArenaAllocator.init(alloc);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var instrs = std.ArrayListUnmanaged(assembly.Instr).empty;

    for (func_def.instrs.items) |instr| {
        // note the different allocators for each function.
        const ret = try instr_to_asm(arena, instr);
        try instrs.appendSlice(alloc, ret);
    }

    return .{
        .name = func_def.name,
        .instrs = instrs,
    };
}

fn instr_to_asm(
    alloc: std.mem.Allocator,
    instr: ir.Instr,
) ![]assembly.Instr {
    switch (instr) {
        .ret => |v| {
            const src = value_to_asm(v);
            return try alloc.dupe(assembly.Instr, &.{
                .{ .mov = .init(src, .{ .reg = .AX }) },
                .ret,
            });
        },
        .unop_complement => |u| {
            const src = value_to_asm(u.src);
            const dst = value_to_asm(u.dst);

            return try alloc.dupe(assembly.Instr, &.{
                .{ .mov = .init(src, dst) },
                .{ .not = dst },
            });
        },
        .unop_negate => |u| {
            const src = value_to_asm(u.src);
            const dst = value_to_asm(u.dst);

            return try alloc.dupe(assembly.Instr, &.{
                .{ .mov = .init(src, dst) },
                .{ .neg = dst },
            });
        },
    }
}

fn value_to_asm(
    value: ir.Value,
) assembly.Operand {
    switch (value) {
        .constant => |c| return .{ .imm = c },
        .variable => |v| return .{ .pseudo = v },
    }
}
