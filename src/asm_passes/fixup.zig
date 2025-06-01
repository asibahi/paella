const std = @import("std");
const assembly = @import("../assembly.zig");

pub fn fixup_instrs(
    alloc: std.mem.Allocator,
    func_def: *assembly.FuncDef,
) !void {
    var out: std.ArrayListUnmanaged(assembly.Instr) = try .initCapacity(
        alloc,
        func_def.instrs.capacity,
    );
    defer {
        std.mem.swap(
            std.ArrayListUnmanaged(assembly.Instr),
            &out,
            &func_def.instrs,
        );
        out.deinit(alloc);
    }

    const State = enum {
        start,
        mov_stack_stack,
        cmp_stack_stack,
        cmp_to_imm,
        add_stack_stack,
        sub_stack_stack,
        mul_to_stack,
        idiv_const,
        legal,
    };

    for (func_def.instrs.items) |instr| {
        state: switch (State.start) {
            .start => switch (instr) {
                .mov => |m| if (m.src == .stack and m.dst == .stack)
                    continue :state .mov_stack_stack
                else
                    continue :state .legal,
                .cmp => |m| if (m.src == .stack and m.dst == .stack)
                    continue :state .cmp_stack_stack
                else if (m.dst == .imm)
                    continue :state .cmp_to_imm
                else
                    continue :state .legal,
                .add => |m| if (m.src == .stack and m.dst == .stack)
                    continue :state .add_stack_stack
                else
                    continue :state .legal,
                .sub => |m| if (m.src == .stack and m.dst == .stack)
                    continue :state .sub_stack_stack
                else
                    continue :state .legal,
                .mul => |m| if (m.dst == .stack)
                    continue :state .mul_to_stack
                else
                    continue :state .legal,
                .idiv => |o| if (o == .imm)
                    continue :state .idiv_const
                else
                    continue :state .legal,

                else => continue :state .legal,
            },

            .mov_stack_stack => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.mov.src, .{ .reg = .R10 }) },
                .{ .mov = .init(.{ .reg = .R10 }, instr.mov.dst) },
            }),
            .cmp_stack_stack => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.cmp.src, .{ .reg = .R10 }) },
                .{ .cmp = .init(.{ .reg = .R10 }, instr.cmp.dst) },
            }),
            .cmp_to_imm => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.cmp.dst, .{ .reg = .R11 }) },
                .{ .cmp = .init(instr.cmp.src, .{ .reg = .R11 }) },
            }),
            .add_stack_stack => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.add.src, .{ .reg = .R10 }) },
                .{ .add = .init(.{ .reg = .R10 }, instr.add.dst) },
            }),
            .sub_stack_stack => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.sub.src, .{ .reg = .R10 }) },
                .{ .sub = .init(.{ .reg = .R10 }, instr.sub.dst) },
            }),
            .mul_to_stack => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.mul.dst, .{ .reg = .R11 }) },
                .{ .mul = .init(instr.mul.src, .{ .reg = .R11 }) },
                .{ .mov = .init(.{ .reg = .R11 }, instr.mul.dst) },
            }),
            .idiv_const => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.idiv, .{ .reg = .R11 }) },
                .{ .idiv = .{ .reg = .R11 } },
            }),

            .legal => try out.append(alloc, instr),
        }
    }
}
