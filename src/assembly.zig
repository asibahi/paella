const std = @import("std");

pub const Prgm = struct {
    func_def: *FuncDef,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{}", .{self.func_def});
    }
};

pub const FuncDef = struct {
    name: []const u8,
    instrs: std.ArrayListUnmanaged(Inst),

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("\t.globl _{0s}\n_{0s}:\n", .{self.name});
        for (self.instrs.items) |instr|
            try writer.print("{}\n", .{instr});
    }
};

pub const Inst = union(enum) {
    mov: struct { src: Operand, dst: Operand },
    ret: void,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .ret => try writer.writeAll("\tret"),
            .mov => |mov| try writer.print("\tmovl {[src]}, {[dst]}", mov),
        }
    }
};

pub const Operand = union(enum) {
    imm: u64,
    reg: void,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .imm => |i| try writer.print("${d}", .{i}),
            .reg => try writer.writeAll("%eax"),
        }
    }
};
