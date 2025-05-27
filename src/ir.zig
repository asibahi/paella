const std = @import("std");
const utils = @import("utils.zig");

pub const Prgm = struct {
    func_def: *FuncDef,

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.func_def.deinit(alloc);
        alloc.destroy(self.func_def);

        // string interner manages its own memory thanks.
    }

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("PRORGAM\n", .{});
        try writer.print("{:[1]}", .{
            self.func_def,
            (options.width orelse 0) + 1,
        });
        try writer.writeByteNTimes('=', 32);
    }
};

pub const FuncDef = struct {
    name: utils.StringInterner.Idx,
    instrs: std.ArrayListUnmanaged(Instr),

    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        self.instrs.deinit(alloc);
    }

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const w = options.width orelse 0;
        try writer.writeByteNTimes('\t', w);

        try writer.print("FUNCTION {any}\n", .{self.name});
        for (self.instrs.items) |instr|
            try writer.print("{:[1]}\n", .{
                instr,
                w + 1,
            });
    }
};

pub const Instr = union(enum) {
    ret: Value,

    copy: Unary,
    jump: utils.StringInterner.Idx,
    jump_z: JumpIf,
    jump_nz: JumpIf,

    label: utils.StringInterner.Idx,

    unop_neg: Unary,
    unop_not: Unary,
    unop_lnot: Unary, // <-- new

    binop_add: Binary,
    binop_sub: Binary,
    binop_mul: Binary,
    binop_div: Binary,
    binop_rem: Binary,

    binop_eql: Binary,
    binop_neq: Binary,
    binop_lt: Binary,
    binop_le: Binary,
    binop_gt: Binary,
    binop_ge: Binary,

    pub const Unary = struct {
        src: Value,
        dst: Value,

        pub fn init(src: Value, dst: Value) @This() {
            return .{ .src = src, .dst = dst };
        }
    };

    pub const Binary = struct {
        src1: Value,
        src2: Value,
        dst: Value,

        pub fn init(src1: Value, src2: Value, dst: Value) @This() {
            return .{ .src1 = src1, .src2 = src2, .dst = dst };
        }
    };

    pub const JumpIf = struct {
        cond: Value,
        target: utils.StringInterner.Idx,

        pub fn init(cond: Value, target: utils.StringInterner.Idx) @This() {
            return .{ .cond = cond, .target = target };
        }
    };

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const w = options.width orelse 0;
        try writer.writeByteNTimes('\t', w);

        switch (self) {
            .ret => |v| try writer.print("ret {}", .{v}),

            .copy => |u| try writer.print("{[dst]} <- {[src]}", u),
            .jump => |l| try writer.print("jump => {}", .{l}),
            .jump_z => |j| try writer.print("jz  {[cond]} => {[target]}", j),
            .jump_nz => |j| try writer.print("jnz {[cond]} => {[target]}", j),

            .label => |l| try writer.print("=> {}", .{l}),

            .unop_neg => |u| try writer.print("{[dst]} <- - {[src]}", u),
            .unop_not => |u| try writer.print("{[dst]} <- ~ {[src]}", u),
            .unop_lnot => |u| try writer.print("{[dst]} <- ! {[src]}", u),

            .binop_add => |b| try writer.print("{[dst]} <- {[src1]} + {[src2]}", b),
            .binop_sub => |b| try writer.print("{[dst]} <- {[src1]} - {[src2]}", b),
            .binop_mul => |b| try writer.print("{[dst]} <- {[src1]} * {[src2]}", b),
            .binop_div => |b| try writer.print("{[dst]} <- {[src1]} / {[src2]}", b),
            .binop_rem => |b| try writer.print("{[dst]} <- {[src1]} % {[src2]}", b),

            .binop_eql => |b| try writer.print("{[dst]} <- {[src1]} == {[src2]}", b),
            .binop_neq => |b| try writer.print("{[dst]} <- {[src1]} != {[src2]}", b),
            .binop_lt => |b| try writer.print("{[dst]} <- {[src1]} < {[src2]}", b),
            .binop_le => |b| try writer.print("{[dst]} <- {[src1]} <= {[src2]}", b),
            .binop_gt => |b| try writer.print("{[dst]} <- {[src1]} > {[src2]}", b),
            .binop_ge => |b| try writer.print("{[dst]} <- {[src1]} >= {[src2]}", b),
        }
    }
};

pub const Value = union(enum) {
    constant: u64,
    variable: utils.StringInterner.Idx,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .constant => |c| try writer.print("{}", .{c}),
            .variable => |n| try writer.print("{}", .{n}),
        }
    }
};
