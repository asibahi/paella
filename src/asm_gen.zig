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
        .unop_not, .unop_neg => |u| {
            const src = value_to_asm(u.src);
            const dst = value_to_asm(u.dst);

            return try alloc.dupe(assembly.Instr, &.{
                .{ .mov = .init(src, dst) },
                switch (instr) {
                    .unop_not => .{ .not = dst },
                    .unop_neg => .{ .neg = dst },
                    else => unreachable,
                },
            });
        },
        .unop_lnot => |u| {
            const src = value_to_asm(u.src);
            const dst = value_to_asm(u.dst);

            return try alloc.dupe(assembly.Instr, &.{
                .{ .cmp = .init(.{ .imm = 0 }, src) },
                .{ .mov = .init(.{ .imm = 0 }, dst) },
                .{ .set_cc = .{ .e, dst } },
            });
        },

        .binop_add, .binop_sub, .binop_mul => |b| {
            const src1 = value_to_asm(b.src1);
            const src2 = value_to_asm(b.src2);
            const dst = value_to_asm(b.dst);

            return try alloc.dupe(assembly.Instr, &.{
                .{ .mov = .init(src1, dst) },
                switch (instr) {
                    .binop_add => .{ .add = .init(src2, dst) },
                    .binop_sub => .{ .sub = .init(src2, dst) },
                    .binop_mul => .{ .mul = .init(src2, dst) },
                    else => unreachable,
                },
            });
        },
        .binop_div, .binop_rem => |b| {
            const src1 = value_to_asm(b.src1);
            const src2 = value_to_asm(b.src2);
            const dst = value_to_asm(b.dst);

            const dst_reg: assembly.Operand.Register =
                if (instr == .binop_div) .AX else .DX;

            return try alloc.dupe(assembly.Instr, &.{
                .{ .mov = .init(src1, .{ .reg = .AX }) },
                .cdq,
                .{ .idiv = src2 },
                .{ .mov = .init(.{ .reg = dst_reg }, dst) },
            });
        },
        .binop_eql, .binop_neq, .binop_lt, .binop_le, .binop_gt, .binop_ge => |b| {
            const src1 = value_to_asm(b.src1);
            const src2 = value_to_asm(b.src2);
            const dst = value_to_asm(b.dst);

            const cc: assembly.Instr.CondCode = switch (instr) {
                .binop_eql => .e,
                .binop_neq => .ne,
                .binop_lt => .l,
                .binop_le => .le,
                .binop_gt => .g,
                .binop_ge => .ge,
                else => unreachable,
            };

            return try alloc.dupe(assembly.Instr, &.{
                .{ .cmp = .init(src2, src1) },
                .{ .mov = .init(.{ .imm = 0 }, dst) },
                .{ .set_cc = .{ cc, dst } },
            });
        },
        .label => |s| return try alloc.dupe(assembly.Instr, &.{
            .{ .label = s },
        }),
        .jump => |s| return try alloc.dupe(assembly.Instr, &.{
            .{ .jmp = s },
        }),
        .jump_z, .jump_nz => |j| return try alloc.dupe(assembly.Instr, &.{
            .{ .cmp = .init(.{ .imm = 0 }, value_to_asm(j.cond)) },
            .{ .jmp_cc = .{ if (instr == .jump_z) .e else .ne, j.target } },
        }),
        .copy => |u| return try alloc.dupe(assembly.Instr, &.{
            .{ .mov = .init(
                value_to_asm(u.src),
                value_to_asm(u.dst),
            ) },
        }),
        // else => @panic("todo"),
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
