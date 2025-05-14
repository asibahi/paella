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

    const State = enum {
        start,
        mov_stack_stack,
        legal,
    };

    for (prgm.func_def.instrs.items) |instr| {
        state: switch (State.start) {
            .start => switch (instr) {
                .mov => |m| if (m.src == .stack and m.dst == .stack)
                    continue :state .mov_stack_stack
                else
                    continue :state .legal,
                else => continue :state .legal,
            },

            .mov_stack_stack => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.mov.src, .{ .reg = .R10 }) },
                .{ .mov = .init(.{ .reg = .R10 }, instr.mov.dst) },
            }),

            .legal => try out.append(alloc, instr),
        }
    }
}
