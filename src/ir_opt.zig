const std = @import("std");
const ir = @import("ir.zig");
const utils = @import("utils.zig");

pub const Optimization = enum {
    @"fold-constants",
    @"propagate-copies",
    @"eliminate-unreachable-code",
    @"eliminate-dead-stores",
};

pub fn optimize(
    gpa: std.mem.Allocator,
    func_def: *ir.FuncDef,
    opts: std.EnumSet(Optimization),
) !void {
    if (func_def.instrs.items.len == 0) return;

    while (true) {
        var work_done = false;

        if (opts.contains(.@"fold-constants"))
            work_done = try fold_constants(gpa, func_def) or work_done;

        var cfg: utils.ControlFlowGraph(ir.Instr) =
            try .init(gpa, func_def.instrs);
        defer cfg.deinit(gpa);

        // if (opts.contains(.@"eliminate-unreachable-code")) {
        //     work_done = true;
        //     cfg = eliminate_unreachable_code(gpa, cfg);
        // }

        // if (opts.contains(.@"propagate-copies")) {
        //     work_done = true;
        //     cfg = propagate_copies(gpa, cfg);
        // }

        // if (opts.contains(.@"eliminate-dead-stores")) {
        //     work_done = true;
        //     cfg = eliminate_dead_stores(gpa, cfg);
        // }

        // const ret_instrs = cfg_to_instrs(cfg);

        if (func_def.instrs.items.len == 0 or !work_done)
            return;

        // instrs = ret_instrs;
    }
}

fn fold_constants(
    gpa: std.mem.Allocator,
    func_def: *ir.FuncDef,
) !bool {
    var out: std.ArrayListUnmanaged(ir.Instr) = try .initCapacity(
        gpa,
        func_def.instrs.capacity,
    );
    defer {
        std.mem.swap(
            std.ArrayListUnmanaged(ir.Instr),
            &out,
            &func_def.instrs,
        );
        out.deinit(gpa);
    }

    var work = false;

    for (func_def.instrs.items) |instr| switch (instr) {
        .unop_neg,
        .unop_not,
        .unop_lnot,
        => |u| if (u.src == .constant) {
            work = true;
            const res: ir.Value = .{ .constant = switch (instr) {
                .unop_neg => -u.src.constant,
                .unop_not => ~u.src.constant,
                .unop_lnot => if (u.src.constant == 0) 1 else 0,
                else => unreachable,
            } };
            try out.append(gpa, .{ .copy = .init(res, u.dst) });
        } else try out.append(gpa, instr),

        .binop_add,
        .binop_sub,
        .binop_mul,
        .binop_div,
        .binop_rem,
        .binop_eql,
        .binop_neq,
        .binop_lt,
        .binop_le,
        .binop_gt,
        .binop_ge,
        => |b| if (b.src1 == .constant and b.src2 == .constant) {
            work = true;
            const lhs, const rhs = .{ b.src1.constant, b.src2.constant };
            const res: ir.Value = .{ .constant = switch (instr) {
                .binop_add => lhs +% rhs,
                .binop_sub => lhs -% rhs,
                .binop_mul => lhs *% rhs,
                .binop_div => if (rhs != 0) @divTrunc(lhs, rhs) else 0,
                .binop_rem => if (rhs != 0) @rem(lhs, rhs) else 0,
                .binop_eql => if (lhs == rhs) 1 else 0,
                .binop_neq => if (lhs != rhs) 1 else 0,
                .binop_lt => if (lhs < rhs) 1 else 0,
                .binop_le => if (lhs <= rhs) 1 else 0,
                .binop_gt => if (lhs > rhs) 1 else 0,
                .binop_ge => if (lhs >= rhs) 1 else 0,
                else => unreachable,
            } };
            try out.append(gpa, .{ .copy = .init(res, b.dst) });
        } else try out.append(gpa, instr),

        .jump_z, .jump_nz => |j| if (j.cond == .constant) {
            work = true;
            if ((instr == .jump_z and j.cond.constant == 0) or
                (instr == .jump_nz and j.cond.constant != 0))
                try out.append(gpa, .{ .jump = j.target });
        } else try out.append(gpa, instr),

        else => try out.append(gpa, instr),
    };

    return work;
}
