const std = @import("std");
const assembly = @import("../assembly.zig");

pub fn fixup_instrs(
    alloc: std.mem.Allocator,
    prgm: *assembly.Prgm,
) !void {
    var out: std.ArrayListUnmanaged(assembly.Instr) = try .initCapacity(
        alloc,
        prgm.func_def.instrs.capacity,
    );
    defer {
        std.mem.swap(
            std.ArrayListUnmanaged(assembly.Instr),
            &out,
            &prgm.func_def.instrs,
        );
        out.deinit(alloc);
    }

    for (prgm.func_def.instrs.items) |instr| {
        switch (instr) {
            .mov => |m| switch (m.src) {
                .stack => switch (m.dst) {
                    .stack => try out.appendSlice(alloc, &.{
                        .{ .mov = .init(m.src, .{ .reg = .R10 }) },
                        .{ .mov = .init(.{ .reg = .R10 }, m.dst) },
                    }),
                    else => try out.append(alloc, instr),
                },
                else => try out.append(alloc, instr),
            },
            else => try out.append(alloc, instr),
        }
    }
}
