const std = @import("std");
const assembly = @import("../assembly.zig");
const utils = @import("../utils.zig");

const PseudoMap = std.StringArrayHashMap(assembly.Operand.Offset);

pub fn replace_pseudos(
    alloc: std.mem.Allocator,
    prgm: *assembly.Prgm,
) !assembly.Instr.Depth {
    var pseudo_map: PseudoMap = .init(alloc);
    defer pseudo_map.deinit();

    for (prgm.func_def.instrs.items) |*instr| {
        switch (instr.*) {
            .mov => |*m| m.* = .init(
                try pseudo_to_stack(m.src, &pseudo_map),
                try pseudo_to_stack(m.dst, &pseudo_map),
            ),
            .neg, .not => |*v| v.* = try pseudo_to_stack(v.*, &pseudo_map),
            .ret, .allocate_stack => {},
        }
    }

    return @intCast(pseudo_map.count() * 4);
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
