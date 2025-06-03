const std = @import("std");
const assembly = @import("../assembly.zig");
const utils = @import("../utils.zig");
const sema = @import("../sema.zig");

const PseudoMap = std.AutoArrayHashMap(
    utils.StringInterner.Idx,
    void,
);

pub fn replace_pseudos(
    alloc: std.mem.Allocator,
    type_map: *const sema.TypeMap,
    func_def: *assembly.FuncDef,
) !void {
    var pseudo_map: PseudoMap = .init(alloc);
    defer pseudo_map.deinit();

    for (func_def.instrs.items) |*instr| {
        switch (instr.*) {
            .mov, .cmp, .add, .sub, .mul => |*m| m.* = .init(
                try pseudo_to_stack(m.src, type_map, &pseudo_map),
                try pseudo_to_stack(m.dst, type_map, &pseudo_map),
            ),
            .neg, .not, .idiv, .push => |*v| v.* = try pseudo_to_stack(
                v.*,
                type_map,
                &pseudo_map,
            ),
            .set_cc => |*s| s.@"1" = try pseudo_to_stack(
                s.@"1",
                type_map,
                &pseudo_map,
            ),

            else => {},
        }
    }
    func_def.depth = @intCast(pseudo_map.count() * 4);

    const aligned = std.mem.alignForward(assembly.Instr.Depth, func_def.depth, 16);
    try func_def.instrs.insert(alloc, 0, .{ .allocate_stack = aligned });
}

fn pseudo_to_stack(
    op: assembly.Operand,
    type_map: *const sema.TypeMap,
    map: *PseudoMap,
) !assembly.Operand {
    switch (op) {
        .reg, .imm, .stack, .data => return op,
        .pseudo => |name| {
            const offset: assembly.Operand.Offset =
                if (map.getIndex(name)) |idx|
                    // already seen
                    @intCast(idx + 1)
                else if (cond: {
                    const cond = type_map.get(name.real_idx);
                    if (cond == null) break :cond false;
                    break :cond cond.? == .static;
                })
                    return .{ .data = name }
                else ret: {
                    try map.put(name, {});
                    break :ret @intCast(map.count()); // index of last item + 1
                };
            return .{ .stack = offset * -4 };
        },
    }
}
