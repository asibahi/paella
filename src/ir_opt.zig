const std = @import("std");
const ir = @import("ir.zig");
const utils = @import("utils.zig");

const CFG = utils.ControlFlowGraph(ir.Instr);

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

        var cfg: CFG = try .init(gpa, func_def.instrs);

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

        try cfg.concat_and_deinit(gpa, &func_def.instrs);
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
    cfg: *CFG,
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

        for (0..cfg.nodes.len) |idx|
            if (!done.contains(idx) and
                cfg.nodes[idx] == .basic_block)
            {
                work = true;
                cfg.delete_node(gpa, idx);
            };
    }

    { // remove redundant jumps
        var idx = cfg.nodes.len - 1;
        var next_idx = idx;
        while (idx > 0) : (idx -= 1) if (cfg.nodes[idx] == .basic_block) {
            defer next_idx = idx;
            if (next_idx == cfg.nodes.len - 1)
                continue; // skip checking the last block

            const last_instr: ir.Instr = lbl: {
                const ii = cfg.nodes[idx].basic_block.getLastOrNull() orelse
                    continue;
                break :lbl cfg.og_instrs[ii];
            };

            if (last_instr == .jump or
                last_instr == .jump_z or
                last_instr == .jump_nz)
            {
                for (cfg.edges.items) |edge| {
                    if (edge.@"0" == idx and edge.@"1" != next_idx)
                        break;
                } else {
                    work = true;
                    _ = cfg.nodes[idx].basic_block.pop();
                }
            }
        };
    }

    { // remove redundant jumps
        var prev_idx: usize = 0;
        for (cfg.nodes, 0..) |*node, idx| if (node.* == .basic_block) {
            defer prev_idx = idx;
            if (node.basic_block.items.len == 0) continue;

            if (cfg.og_instrs[node.basic_block.items[0]] == .label)
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

fn find_reaching_copies(
    gpa: std.mem.Allocator,
    cfg: *CFG,
    meet: fn (CFG.NodeIdx, []CFG.InstrIdx) []CFG.InstrIdx,
    transfer: fn (CFG.NodeIdx, []CFG.InstrIdx) void,
) !void {
    const all_copies = a: {
        var idxs: std.ArrayListUnmanaged(usize) = .empty;
        for (cfg.og_instrs, 0..) |instr, idx|
            if (instr == .copy)
                try idxs.append(gpa, idx);

        break :a try idxs.toOwnedSlice(gpa);
    };

    var worklist: std.fifo.LinearFifo(
        CFG.NodeIdx,
        .Dynamic,
    ) = .initDynamic(gpa);

    for (cfg.nodes.items, 0..) |*node, idx| if (node.* == .basic_block) {
        try worklist.writeItem(idx);
        cfg.annotate_block(idx, all_copies);
    };

    while (worklist.readItem()) |block_idx| {
        // should use scratch memory
        const old_annotation =
            try gpa.dupe([]usize, cfg.node_annotations[block_idx]);
        defer gpa.free(old_annotation);

        const incoming_copies = meet(block_idx, all_copies);
        transfer(block_idx, incoming_copies);

        if (!std.mem.eql(
            []usize,
            old_annotation,
            cfg.node_annotations[block_idx],
        )) {
            for (cfg.edges.items) |edge| if (edge.@"0" == block_idx) {
                const successor_id = edge.@"1";
                switch (cfg.nodes.items[successor_id]) {
                    .entry, .tombstone => return error.MalformedCFG,
                    .exit => continue,
                    .basic_block => |succ_idx| if (!std.mem.containsAtLeastScalar(
                        usize,
                        worklist.readableSlice(0),
                        1,
                        succ_idx,
                    )) try worklist.writeItem(succ_idx),
                }
            };
        }
    }
}
