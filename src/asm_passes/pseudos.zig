const std = @import("std");
const assembly = @import("../assembly.zig");
const utils = @import("../utils.zig");

pub fn replace_pseudos(
    alloc: std.mem.Allocator,
    strings: *utils.StringInterner,
    prgm: *assembly.Prgm,
) !assembly.Operand.StackDepth {
    var pseudo_map: std.AutoHashMap(
        utils.StringInterner.Idx,
        assembly.Operand.StackDepth,
    ) = .init(alloc);
    defer pseudo_map.deinit();

    var counter: assembly.Operand.StackDepth = 0;

    for (prgm.func_def.instrs.items) |*instr| {
        switch (instr.*) {
            .mov => |*m| {
                const src = try pseudo_to_stack(m.src, &counter, strings, &pseudo_map);
                const dst = try pseudo_to_stack(m.dst, &counter, strings, &pseudo_map);

                m.* = .init(src, dst);
            },
            .neg, .not => |*v| v.* = try pseudo_to_stack(v.*, &counter, strings, &pseudo_map),

            .ret, .allocate_stack => {},
        }
    }

    return counter;
}

fn pseudo_to_stack(
    op: assembly.Operand,
    counter: *assembly.Operand.StackDepth,
    strings: *utils.StringInterner,
    map: *std.AutoHashMap(
        utils.StringInterner.Idx,
        assembly.Operand.StackDepth,
    ),
) !assembly.Operand {
    switch (op) {
        .reg, .imm, .stack => return op,
        .pseudo => |name| {
            const idx = strings.get_idx(name).?;
            const gop = try map.getOrPut(idx);

            if (gop.found_existing) {
                return .{ .stack = gop.value_ptr.* };
            } else {
                counter.* -= 4;

                gop.key_ptr.* = idx;
                gop.value_ptr.* = counter.*;

                return .{ .stack = gop.value_ptr.* };
            }
        },
    }
}
