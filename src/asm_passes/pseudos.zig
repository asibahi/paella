const std = @import("std");
const assembly = @import("../assembly.zig");
const utils = @import("../utils.zig");

pub fn replace_pseudos(
    alloc: std.mem.Allocator,
    prgm: *assembly.Prgm,
) !assembly.Operand.StackDepth {
    var pseudo_map: std.StringHashMap(
        assembly.Operand.StackDepth,
    ) = .init(alloc);
    defer pseudo_map.deinit();

    var counter: assembly.Operand.StackDepth = 0;

    for (prgm.func_def.instrs.items) |*instr| {
        switch (instr.*) {
            .mov => |*m| {
                const src = try pseudo_to_stack(m.src, &counter, &pseudo_map);
                const dst = try pseudo_to_stack(m.dst, &counter, &pseudo_map);

                m.* = .init(src, dst);
            },
            .neg, .not => |*v| v.* = try pseudo_to_stack(v.*, &counter, &pseudo_map),

            .ret, .allocate_stack => {},
        }
    }

    return counter;
}

fn pseudo_to_stack(
    op: assembly.Operand,
    counter: *assembly.Operand.StackDepth,
    map: *std.StringHashMap(assembly.Operand.StackDepth),
) !assembly.Operand {
    switch (op) {
        .reg, .imm, .stack => return op,
        .pseudo => |name| {
            const gop = try map.getOrPut(name);

            if (gop.found_existing) {
                return .{ .stack = gop.value_ptr.* };
            } else {
                counter.* -= 4;
                gop.value_ptr.* = counter.*;

                return .{ .stack = gop.value_ptr.* };
            }
        },
    }
}
