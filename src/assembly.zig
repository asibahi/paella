const std = @import("std");

pub const Prgm = struct {
    func_def: *FuncDef,

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
    instrs: std.ArrayListUnmanaged(Inst),

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

pub const Inst = union(enum) {
    mov: struct { src: Operand, dst: Operand },
    ret: void,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) {
            switch (self) {
                .ret => try writer.writeAll("\tret"),
                .mov => |mov| try writer.print("\tmovl {[src]gen}, {[dst]gen}", mov),
            }
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            switch (self) {
                .ret => try writer.writeAll("ret"),
                .mov => |mov| try writer.print("mov {[src]}, {[dst]}", mov),
            }
        }
    }
};

pub const Operand = union(enum) {
    imm: u64,
    reg: void,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) {
            switch (self) {
                .imm => |i| try writer.print("${d}", .{i}),
                .reg => try writer.writeAll("%eax"),
            }
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            switch (self) {
                .imm => |i| try writer.print("imm {d}", .{i}),
                .reg => try writer.writeAll("register"),
            }
        }
    }
};
