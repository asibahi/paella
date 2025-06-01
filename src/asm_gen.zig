const std = @import("std");
const ir = @import("ir.zig");
const assembly = @import("assembly.zig");
const utils = @import("utils.zig");

const REGISTERS: [6]assembly.Operand.Register =
    .{ .DI, .SI, .DX, .CX, .R8, .R9 };

pub fn prgm_to_asm(
    alloc: std.mem.Allocator,
    prgm: ir.Prgm,
) !assembly.Prgm {
    var funcs: std.ArrayListUnmanaged(assembly.FuncDef) = try .initCapacity(
        alloc,
        prgm.funcs.items.len,
    );

    for (prgm.funcs.items) |func|
        try funcs.append(
            alloc,
            try func_def_to_asm(alloc, func),
        );

    return .{ .funcs = funcs };
}

fn func_def_to_asm(
    alloc: std.mem.Allocator,
    func_def: ir.FuncDef,
) !assembly.FuncDef {
    var scratch = std.heap.ArenaAllocator.init(alloc);
    defer scratch.deinit();

    var instrs = std.ArrayListUnmanaged(assembly.Instr).empty;

    for (func_def.params.items, 0..) |param, idx|
        if (idx < REGISTERS.len)
            try instrs.append(alloc, .{ .mov = .init(
                .{ .reg = REGISTERS[idx] },
                .{ .pseudo = param },
            ) })
        else {
            const offset = (idx - REGISTERS.len + 2) * 8;
            try instrs.append(alloc, .{ .mov = .init(
                .{ .stack = @intCast(offset) },
                .{ .pseudo = param },
            ) });
        };

    for (func_def.instrs.items) |instr| {
        // note the different allocators for each function.
        const ret = try instr_to_asm(scratch.allocator(), instr);
        defer _ = scratch.reset(.retain_capacity); // maybe?

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

        .func_call => |c| {
            // the return is of unknown size.
            // maximum possible size is parameter count * 2 + 4
            var ret: std.ArrayListUnmanaged(assembly.Instr) =
                try .initCapacity(alloc, c.args.items.len * 2 + 4);

            const depth = c.args.items.len -| REGISTERS.len;
            const padding: assembly.Instr.Depth =
                if (depth % 2 == 0) 0 else 8;
            if (padding > 0)
                try ret.append(alloc, .{ .allocate_stack = padding }); // 1

            for (c.args.items, 0..) |arg, idx| {
                if (idx >= REGISTERS.len) break;

                try ret.append(alloc, .{ .mov = .init(
                    value_to_asm(arg),
                    .{ .reg = REGISTERS[idx] },
                ) });
            }
            for (0..depth) |idx| {
                const v_ir = c.args.items[c.args.items.len - 1 - idx];
                const v_asm = value_to_asm(v_ir);
                switch (v_asm) {
                    .imm, .reg => try ret.append(alloc, .{ .push = v_asm }),
                    else => try ret.appendSlice(alloc, &.{
                        .{ .mov = .init(v_asm, .{ .reg = .AX }) },
                        .{ .push = .{ .reg = .AX } },
                    }),
                }
            }

            // emit call instruction
            try ret.append(alloc, .{ .call = c.name }); // 2

            const bytes_to_remove = 8 * depth + padding;
            if (bytes_to_remove != 0)
                try ret.append(alloc, .{ .dealloc_stack = bytes_to_remove }); // 3

            try ret.append(alloc, .{ .mov = .init(
                .{ .reg = .AX },
                value_to_asm(c.dst),
            ) }); // 4

            return ret.items;
        },
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
