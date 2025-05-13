const std = @import("std");

const utils = @import("utils.zig");

const pass_pseudo = @import("asm_passes/pseudos.zig");
const pass_fixup = @import("asm_passes/fixup.zig");

pub const Prgm = struct {
    func_def: *FuncDef,

    pub fn fixup(
        self: *@This(),
        alloc: std.mem.Allocator,
        strings: *utils.StringInterner,
    ) !void {
        // this code here should reasonably live in FuncDef
        const depth = try pass_pseudo.replace_pseudos(alloc, strings, self);
        try self.func_def.instrs.insert(alloc, 0, .{
            .allocate_stack = @abs(depth),
        });
        try pass_fixup.fixup_instrs(alloc, self);
    }

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.func_def.deinit(alloc);
        alloc.destroy(self.func_def);
    }

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) {
            try writer.print("{gen}", .{self.func_def});
        } else {
            try writer.print("PRORGAM\n", .{});
            try writer.print("{:[1]}", .{
                self.func_def,
                (options.width orelse 0) + 1,
            });
        }
    }
};

pub const FuncDef = struct {
    name: []const u8,
    instrs: std.ArrayListUnmanaged(Instr),

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.instrs.deinit(alloc);
    }

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) {
            try writer.print("\t.globl _{0s}\n_{0s}:\n", .{self.name});
            for (self.instrs.items) |instr|
                try writer.print("{gen}\n", .{instr});
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            try writer.print("FUNCTION {s}\n", .{self.name});
            for (self.instrs.items) |instr|
                try writer.print("{:[1]}\n", .{
                    instr,
                    w + 1,
                });
        }
    }
};

pub const Instr = union(enum) {
    mov: Mov,
    ret: void,

    // unary operations
    neg: Operand,
    not: Operand,

    // weird and useless type magic happens here. just write u64
    allocate_stack: std.meta.Int(.unsigned, @bitSizeOf(Operand.StackDepth)),

    const Mov = struct {
        src: Operand,
        dst: Operand,

        pub fn init(src: Operand, dst: Operand) @This() {
            return .{ .src = src, .dst = dst };
        }
    };

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) {
            switch (self) {
                .ret => try writer.writeAll("\tret"),
                .mov => |mov| try writer.print(
                    "\tmovl    {[src]gen}, {[dst]gen}",
                    mov,
                ),
                else => @panic("unimplemented"),
            }
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            switch (self) {
                .ret => try writer.writeAll("ret"),
                .mov => |mov| try writer.print("mov\t{[src]} -> {[dst]}", mov),
                .neg => |o| try writer.print("neg\t{}", .{o}),
                .not => |o| try writer.print("not\t{}", .{o}),
                .allocate_stack => |d| try writer.print("allocate\t{d}", .{d}),
            }
        }
    }
};

pub const Operand = union(enum) {
    imm: u64,
    reg: Register,
    pseudo: [:0]const u8,
    stack: StackDepth,

    pub const Register = enum { AX, R10 };
    pub const StackDepth = i64;

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) {
            switch (self) {
                .imm => |i| try writer.print("${d}", .{i}),
                else => @panic("unimplemented"),
            }
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            switch (self) {
                .imm => |i| try writer.print("imm {d}", .{i}),
                .reg => |r| try writer.print("{s}", .{@tagName(r)}),
                .pseudo => |s| try writer.print("pseudo {s}", .{s}),
                .stack => |d| try writer.print("stack {d}", .{d}),
            }
        }
    }
};
