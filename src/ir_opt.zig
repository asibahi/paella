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

    var work_done = true;
    while (func_def.instrs.items.len > 0 and work_done) {
        work_done = false;

        if (opts.contains(.@"fold-constants"))
            work_done = try fold_constants(gpa, func_def) or work_done;

        var cfg: utils.ControlFlowGraph(ir.Instr) =
            try .init(gpa, func_def.instrs);
        defer cfg.deinit(gpa);

        if (opts.contains(.@"eliminate-unreachable-code"))
            work_done = try eliminate_unreachable_code(gpa, &cfg) or work_done;

        // if (opts.contains(.@"propagate-copies")) {
        //     work_done = true;
        //     cfg = propagate_copies(gpa, cfg);
        // }

        // if (opts.contains(.@"eliminate-dead-stores")) {
        //     work_done = true;
        //     cfg = eliminate_dead_stores(gpa, cfg);
        // }

        try cfg.concat(gpa, &func_def.instrs);
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

fn eliminate_unreachable_code(
    gpa: std.mem.Allocator,
    cfg: *utils.ControlFlowGraph(ir.Instr),
) !bool {
    var work = false;

    { // unreachable blocks
        var done: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer done.deinit(gpa);

        var stack: std.ArrayListUnmanaged(usize) = .empty;
        defer stack.deinit(gpa);

        try stack.append(gpa, 0); // entry
        while (stack.pop()) |current|
            if (!done.contains(current)) {
                for (cfg.edges.items) |edge|
                    if (edge.@"0" == current)
                        try stack.append(gpa, edge.@"1");

                try done.put(gpa, current, {});
            };

        for (0..cfg.nodes.items.len) |idx|
            if (!done.contains(idx) and
                cfg.nodes.items[idx] == .basic_block)
            {
                work = true;
                cfg.delete_node(gpa, idx);
            };
    }

    { // remove redundant jumps
        var idx = cfg.nodes.items.len - 1;
        var next_idx = idx;
        while (idx > 0) : (idx -= 1) if (cfg.nodes.items[idx] == .basic_block) {
            defer next_idx = idx;
            if (next_idx == cfg.nodes.items.len - 1)
                continue; // skip checking the last block

            const last_instr: ir.Instr =
                cfg.nodes.items[idx].basic_block.getLastOrNull() orelse
                continue;

            if (last_instr == .jump or
                last_instr == .jump_z or
                last_instr == .jump_nz)
            {
                for (cfg.edges.items) |edge| {
                    if (edge.@"0" == idx and edge.@"1" != next_idx)
                        break;
                } else {
                    work = true;
                    _ = cfg.nodes.items[idx].basic_block.pop();
                }
            }
        };
    }

    { // remove redundant jumps
        var prev_idx: usize = 0;
        for (cfg.nodes.items, 0..) |*node, idx| if (node.* == .basic_block) {
            defer prev_idx = idx;
            if (node.basic_block.items.len == 0) continue;

            if (node.basic_block.items[0] == .label)
                for (cfg.edges.items) |edge| {
                    if (edge.@"0" != prev_idx and edge.@"1" == idx)
                        break;
                } else {
                    work = true;
                    _ = node.basic_block.orderedRemove(0);
                };
        };
    }

    return work;
}
