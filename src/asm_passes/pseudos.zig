const std = @import("std");
const assembly = @import("../assembly.zig");
const utils = @import("../utils.zig");

const PseudoMap = std.AutoArrayHashMap(
    utils.StringInterner.Idx,
    assembly.Operand.Offset,
);

pub fn replace_pseudos(
    alloc: std.mem.Allocator,
    func_def: *assembly.FuncDef,
) !void {
    var pseudo_map: PseudoMap = .init(alloc);
    defer pseudo_map.deinit();

    for (func_def.instrs.items) |*instr| {
        switch (instr.*) {
            .mov, .cmp, .add, .sub, .mul => |*m| m.* = .init(
                try pseudo_to_stack(m.src, &pseudo_map),
                try pseudo_to_stack(m.dst, &pseudo_map),
            ),
            .neg, .not, .idiv, .push => |*v| v.* = try pseudo_to_stack(v.*, &pseudo_map),
            .set_cc => |*s| s.@"1" = try pseudo_to_stack(s.@"1", &pseudo_map),

            else => {},
        }
    }
    func_def.depth = @intCast(pseudo_map.count() * 4);

    const aligned = std.mem.alignForward(assembly.Instr.Depth, func_def.depth, 16);
    try func_def.instrs.insert(alloc, 0, .{ .allocate_stack = aligned });
}

fn pseudo_to_stack(
    op: assembly.Operand,
    map: *PseudoMap,
) !assembly.Operand {
    switch (op) {
        .reg, .imm, .stack => return op,
        .pseudo => |name| {
            const gop = try map.getOrPut(name);
            const offset: assembly.Operand.Offset = @intCast(gop.index + 1);

            // this bit of cleverness will bite me when there are offsets by 8.
            return .{ .stack = offset * -4 };
        },
    }
}
