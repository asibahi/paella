const std = @import("std");
const utils = @import("utils.zig");
const Identifier = utils.StringInterner.Idx;

const pass_pseudo = @import("asm_passes/pseudos.zig");
const pass_fixup = @import("asm_passes/fixup.zig");

pub const Prgm = struct {
    funcs: std.ArrayListUnmanaged(FuncDef),

    pub fn fixup(
        self: *@This(),
        alloc: std.mem.Allocator,
    ) !void {
        for (self.funcs.items) |*func| {
            try pass_pseudo.replace_pseudos(alloc, func);
            try pass_fixup.fixup_instrs(alloc, func);
        }
    }

    pub fn deinit(
        self: *@This(),
        alloc: std.mem.Allocator,
    ) void {
        for (self.funcs.items) |*func|
            func.deinit(alloc);
        self.funcs.deinit(alloc);
    }

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) {
            for (self.funcs.items) |func|
                try writer.print("{" ++ fmt ++ "}", .{func});
        } else {
            try writer.print("PROGRAM\n", .{});
            for (self.funcs.items) |func|
                try writer.print("{:[1]}", .{
                    func,
                    (options.width orelse 0) + 1,
                });
        }
        try writer.writeByteNTimes(';', 32); // `;` is a comment in assembly.
    }
};

pub const FuncDef = struct {
    name: Identifier,
    instrs: std.ArrayListUnmanaged(Instr),
    depth: Instr.Depth = 0,

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

            try writer.print("FUNCTION {}\n", .{self.name});
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
    jmp: Identifier,
    jmp_cc: struct { CondCode, Identifier },
    set_cc: struct { CondCode, Operand },
    label: Identifier,

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
    dealloc_stack: Depth,

    push: Operand,
    call: Identifier,

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

            .jmp => |s| try writer.print("\tjmp    .L{}", .{s}),
            .jmp_cc => |s| try writer.print("\tj{s: <7}.L{}", .{ @tagName(s.@"0"), s.@"1" }),
            .set_cc => |s| try writer.print("\tset{s:<7}{gen:1}", .{ @tagName(s.@"0"), s.@"1" }),
            .label => |s| try writer.print(".L{}:", .{s}),

            .neg => |o| try writer.print("\tnegl    {gen}", .{o}),
            .not => |o| try writer.print("\tnotl    {gen}", .{o}),
            .add => |m| try writer.print("\taddl    {[src]gen}, {[dst]gen}", m),
            .sub => |m| try writer.print("\tsubl    {[src]gen}, {[dst]gen}", m),
            .mul => |m| try writer.print("\timull   {[src]gen}, {[dst]gen}", m),
            .idiv => |o| try writer.print("\tidivl   {gen}", .{o}),

            .cdq => try writer.print("\tcdq", .{}),
            .allocate_stack => |d| try writer.print("\tsubq    ${d}, %rsp", .{d}),
            .dealloc_stack => |d| try writer.print("\taddq    ${d}, %rsp", .{d}),

            .push => |o| try writer.print("\tpushq   {gen:8}", .{o}),
            .call => |s| try writer.print("\tcall    _{}", .{s}),
            // else => @panic("unimplemented"),
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            switch (self) {
                .ret => try writer.writeAll("ret"),
                .mov => |m| try writer.print("mov\t{[src]} -> {[dst]}", m),
                .cmp => |m| try writer.print("cmp\t{[src]} -> {[dst]}", m),

                .jmp => |s| try writer.print("jmp\t.L{}", .{s}),
                .jmp_cc => |s| try writer.print("jmp{s}\t.L{}", .{ @tagName(s.@"0"), s.@"1" }),
                .set_cc => |s| try writer.print("set{s}\t{}", .{ @tagName(s.@"0"), s.@"1" }),
                .label => |s| try writer.print("=> .L{}", .{s}),

                .neg => |o| try writer.print("neg\t{}", .{o}),
                .not => |o| try writer.print("not\t{}", .{o}),
                .add => |m| try writer.print("add\t{[src]} -> {[dst]}", m),
                .sub => |m| try writer.print("sub\t{[src]} -> {[dst]}", m),
                .mul => |m| try writer.print("mul\t{[src]} -> {[dst]}", m),
                .idiv => |o| try writer.print("idiv\t{}", .{o}),

                .cdq => try writer.print("cdq", .{}),
                .allocate_stack => |d| try writer.print("allocate\t{d}", .{d}),
                .dealloc_stack => |d| try writer.print("deallocate\t{d}", .{d}),

                .push => |o| try writer.print("push\t{}", .{o}),
                .call => |s| try writer.print("call\t{}", .{s}),
            }
        }
    }
};

pub const Operand = union(enum) {
    imm: u64,
    reg: Register,
    pseudo: Identifier,
    stack: Offset,

    pub const Register = enum { AX, CX, DX, DI, SI, R8, R9, R10, R11 };
    pub const Offset = i64;

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        if (std.mem.eql(u8, fmt, "gen")) switch (self) {
            .imm => |i| try writer.print("${d}", .{i}),
            .reg => |r| try emit_register(r, options.width orelse 4, writer),
            .stack => |d| try writer.print("{d}(%rbp)", .{d}),
            .pseudo => @panic("wrong code path"),
        } else {
            const w = options.width orelse 0;
            try writer.writeByteNTimes('\t', w);

            switch (self) {
                .imm => |i| try writer.print("imm {d}", .{i}),
                .reg => |r| try writer.print("{s}", .{@tagName(r)}),
                .pseudo => |s| try writer.print("pseudo {}", .{s}),
                .stack => |d| try writer.print("stack {d}", .{d}),
            }
        }
    }
};

fn emit_register(
    reg: Operand.Register,
    width: usize,
    writer: anytype,
) !void {
    p: switch (width) {
        1 => switch (reg) {
            .AX => try writer.print("%al", .{}),
            .DX => try writer.print("%dl", .{}),
            .CX => try writer.print("%cl", .{}),
            .DI => try writer.print("%dil", .{}),
            .SI => try writer.print("%sil", .{}),
            .R8 => try writer.print("%r8b", .{}),
            .R9 => try writer.print("%r9b", .{}),
            .R10 => try writer.print("%r10b", .{}),
            .R11 => try writer.print("%r11b", .{}),
        },
        4 => switch (reg) {
            .AX => try writer.print("%eax", .{}),
            .DX => try writer.print("%edx", .{}),
            .CX => try writer.print("%ecx", .{}),
            .DI => try writer.print("%edi", .{}),
            .SI => try writer.print("%esi", .{}),
            .R8 => try writer.print("%r8d", .{}),
            .R9 => try writer.print("%r9d", .{}),
            .R10 => try writer.print("%r10d", .{}),
            .R11 => try writer.print("%r11d", .{}),
        },
        8 => switch (reg) {
            .AX => try writer.print("%rax", .{}),
            .DX => try writer.print("%rdx", .{}),
            .CX => try writer.print("%rcx", .{}),
            .DI => try writer.print("%rdi", .{}),
            .SI => try writer.print("%rsi", .{}),
            .R8 => try writer.print("%r8", .{}),
            .R9 => try writer.print("%r9", .{}),
            .R10 => try writer.print("%r10", .{}),
            .R11 => try writer.print("%r11", .{}),
        },
        else => continue :p 4, // default case
    }
}

inline fn indent(
    comptime text: []const u8,
) []const u8 {
    comptime {
        var iter = std.mem.splitScalar(u8, text, '\n');
        var res: []const u8 = "";

        while (iter.next()) |line| {
            const tab = if (line.len == 0 or
                std.mem.endsWith(u8, line, ":")) "" else "\t";
            res = res ++ tab ++ line ++ "\n";
        }

        return res[0 .. res.len - 1];
    }
}
