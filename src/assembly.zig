const std = @import("std");

const utils = @import("utils.zig");

const pass_pseudo = @import("asm_passes/pseudos.zig");
const pass_fixup = @import("asm_passes/fixup.zig");

pub const Prgm = struct {
    func_def: *FuncDef,

    pub fn fixup(
        self: *@This(),
        alloc: std.mem.Allocator,
    ) !void {
        // this code here should reasonably live in FuncDef
        const depth = try pass_pseudo.replace_pseudos(alloc, self);
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
        if (std.mem.eql(u8, fmt, "gen"))
            try writer.print("{gen}", .{self.func_def})
        else {
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
            try writer.print(indent(
                \\.globl _{0s}
                \\_{0s}:
                \\pushq   %rbp
                \\movq    %rsp, %rbp
                \\
            ), .{self.name});
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

    cmp: Mov,
    jmp: [:0]const u8,
    jmp_cc: struct { CondCode, [:0]const u8 },
    set_cc: struct { CondCode, Operand },
    label: [:0]const u8,

    // unary operations
    neg: Operand,
    not: Operand,

    // binary operations
    add: Mov,
    sub: Mov,
    mul: Mov,
    idiv: Operand,

    cdq: void,
    allocate_stack: Depth,

    const Mov = struct {
        src: Operand,
        dst: Operand,

        pub fn init(src: Operand, dst: Operand) @This() {
            return .{ .src = src, .dst = dst };
        }
    };
    pub const Depth = std.meta.Int(.unsigned, @bitSizeOf(Operand.Offset));
    pub const CondCode = enum { e, ne, g, ge, l, le };

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) switch (self) {
            .mov => |m| try writer.print(indent(
                \\movl    {[src]gen}, {[dst]gen}
            ), m),
            .cmp => |m| try writer.print(indent(
                \\cmpl    {[src]gen}, {[dst]gen}
            ), m),
            .ret => try writer.writeAll(indent(
                \\movq    %rbp, %rsp
                \\popq    %rbp
                \\ret
            )),

            .jmp => |s| try writer.print("\tjmp    .L{s}", .{s}),
            .jmp_cc => |s| try writer.print("\tj{s: <7}.L{s}", .{ @tagName(s.@"0"), s.@"1" }),
            .set_cc => |s| try writer.print("\tset{s:<7}{gen:1}", .{ @tagName(s.@"0"), s.@"1" }),
            .label => |s| try writer.print(".L{s}:", .{s}),

            .neg => |o| try writer.print("\tnegl    {gen}", .{o}),
            .not => |o| try writer.print("\tnotl    {gen}", .{o}),
            .add => |m| try writer.print("\taddl    {[src]gen}, {[dst]gen}", m),
            .sub => |m| try writer.print("\tsubl    {[src]gen}, {[dst]gen}", m),
            .mul => |m| try writer.print("\timull   {[src]gen}, {[dst]gen}", m),
            .idiv => |o| try writer.print("\tidivl   {gen}", .{o}),

            .cdq => try writer.print("\tcdq", .{}),
            .allocate_stack => |d| try writer.print("\tsubq    ${d}, %rsp", .{d}),

            // else => @panic("unimplemented"),
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            switch (self) {
                .ret => try writer.writeAll("ret"),
                .mov => |m| try writer.print("mov\t{[src]} -> {[dst]}", m),
                .cmp => |m| try writer.print("cmp\t{[src]} -> {[dst]}", m),

                .jmp => |s| try writer.print("jmp\t.L{s}", .{s}),
                .jmp_cc => |s| try writer.print("jmp{s}\t.L{s}", .{ @tagName(s.@"0"), s.@"1" }),
                .set_cc => |s| try writer.print("set{s}\t{}", .{ @tagName(s.@"0"), s.@"1" }),
                .label => |s| try writer.print("=> .L{s}", .{s}),

                .neg => |o| try writer.print("neg\t{}", .{o}),
                .not => |o| try writer.print("not\t{}", .{o}),
                .add => |m| try writer.print("add\t{[src]} -> {[dst]}", m),
                .sub => |m| try writer.print("sub\t{[src]} -> {[dst]}", m),
                .mul => |m| try writer.print("mul\t{[src]} -> {[dst]}", m),
                .idiv => |o| try writer.print("idiv\t{}", .{o}),
                .cdq => try writer.print("cdq", .{}),
                .allocate_stack => |d| try writer.print("allocate\t{d}", .{d}),
            }
        }
    }
};

pub const Operand = union(enum) {
    imm: u64,
    reg: Register,
    pseudo: [:0]const u8,
    stack: Offset,

    pub const Register = enum { AX, DX, R10, R11 };
    pub const Offset = i64;

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) switch (self) {
            .imm => |i| try writer.print("${d}", .{i}),
            .reg => |r| if (options.width == 1) switch (r) {
                .AX => try writer.print("%a1", .{}),
                .DX => try writer.print("%d1", .{}),
                .R10 => try writer.print("%r10b", .{}),
                .R11 => try writer.print("%r11b", .{}),
            } else switch (r) {
                .AX => try writer.print("%eax", .{}),
                .DX => try writer.print("%edx", .{}),
                .R10 => try writer.print("%r10d", .{}),
                .R11 => try writer.print("%r11d", .{}),
            },
            .stack => |d| try writer.print("{d}(%rsp)", .{d}),
            .pseudo => @panic("wrong code path"),
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

inline fn indent(
    comptime text: []const u8,
) []const u8 {
    comptime {
        var iter = std.mem.splitScalar(u8, text, '\n');
        var res: []const u8 = "";

        while (iter.next()) |line|
            res = if (line.len > 0 and !std.mem.endsWith(u8, line, ":"))
                res ++ "\t" ++ line ++ "\n"
            else
                res ++ line ++ "\n";

        return res[0 .. res.len - 1];
    }
}
