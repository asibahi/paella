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
        mov_mem_mem,
        cmp_mem_mem,
        cmp_to_imm,
        add_mem_mem,
        sub_mem_mem,
        mul_to_mem,
        idiv_const,
        legal,
    };

    for (func_def.instrs.items) |instr| {
        state: switch (State.start) {
            .start => switch (instr) {
                .mov => |m| if (m.src.is_mem() and m.dst.is_mem())
                    continue :state .mov_mem_mem
                else
                    continue :state .legal,
                .cmp => |m| if (m.src.is_mem() and m.dst.is_mem())
                    continue :state .cmp_mem_mem
                else if (m.dst == .imm)
                    continue :state .cmp_to_imm
                else
                    continue :state .legal,
                .add => |m| if (m.src.is_mem() and m.dst.is_mem())
                    continue :state .add_mem_mem
                else
                    continue :state .legal,
                .sub => |m| if (m.src.is_mem() and m.dst.is_mem())
                    continue :state .sub_mem_mem
                else
                    continue :state .legal,
                .mul => |m| if (m.dst.is_mem())
                    continue :state .mul_to_mem
                else
                    continue :state .legal,
                .idiv => |o| if (o == .imm)
                    continue :state .idiv_const
                else
                    continue :state .legal,

                else => continue :state .legal,
            },

            .mov_mem_mem => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.mov.src, .{ .reg = .R10 }) },
                .{ .mov = .init(.{ .reg = .R10 }, instr.mov.dst) },
            }),
            .cmp_mem_mem => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.cmp.src, .{ .reg = .R10 }) },
                .{ .cmp = .init(.{ .reg = .R10 }, instr.cmp.dst) },
            }),
            .cmp_to_imm => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.cmp.dst, .{ .reg = .R11 }) },
                .{ .cmp = .init(instr.cmp.src, .{ .reg = .R11 }) },
            }),
            .add_mem_mem => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.add.src, .{ .reg = .R10 }) },
                .{ .add = .init(.{ .reg = .R10 }, instr.add.dst) },
            }),
            .sub_mem_mem => try out.appendSlice(alloc, &.{
                .{ .mov = .init(instr.sub.src, .{ .reg = .R10 }) },
                .{ .sub = .init(.{ .reg = .R10 }, instr.sub.dst) },
            }),
            .mul_to_mem => try out.appendSlice(alloc, &.{
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
