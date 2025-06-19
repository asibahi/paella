const std = @import("std");
const utils = @import("utils.zig");
const sema = @import("sema.zig");
const opt = @import("ir_opt.zig");
const Identifier = utils.StringInterner.Idx;

pub const Prgm = struct {
    items: std.ArrayListUnmanaged(TopLevel),
    type_map: *sema.TypeMap,

    pub fn optimize(
        self: *@This(),
        alloc: std.mem.Allocator,
        opts: std.EnumSet(opt.Optimization),
    ) !void {
        for (self.items.items) |*item| if (item.* == .F)
            try opt.optimize(alloc, &item.F, opts);
    }

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        for (self.items.items) |*item| if (item.* == .F)
            item.F.deinit(alloc);

        self.items.deinit(alloc);

        // string interner manages its own memory thanks.
    }

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("PROGRAM\n", .{});
        for (self.items.items) |item|
            try writer.print("{:[1]}", .{
                item,
                (options.width orelse 0) + 1,
            });
        try writer.writeByteNTimes('=', 32);
    }
};

pub const TopLevel = union(enum) {
    F: FuncDef,
    V: StaticVar,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            inline else => |i| try i.format(fmt, options, writer),
        }
    }
};

pub const FuncDef = struct {
    name: Identifier,
    global: bool = false, // assigned later than contruction
    params: std.ArrayListUnmanaged(Identifier),
    instrs: std.ArrayListUnmanaged(Instr),

    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        for (self.instrs.items) |*i| i.deinit(alloc);
        self.params.deinit(alloc);
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

        if (self.global) try writer.writeAll("global ");
        try writer.print("FUNCTION {} ", .{self.name});
        for (self.params.items, 0..) |param, idx| {
            if (idx > 0) try writer.writeAll(", ");
            try writer.print("{}", .{param});
        }
        try writer.writeByte('\n');
        for (self.instrs.items) |instr|
            try writer.print("{:[1]}\n", .{
                instr,
                w + 1,
            });
    }
};

pub const StaticVar = struct {
    name: Identifier,
    global: bool,
    init: i32,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const w = options.width orelse 0;
        try writer.writeByteNTimes('\t', w);

        if (self.global) try writer.writeAll("global ");
        try writer.print("VARIABLE {} = {}\n", .{ self.name, self.init });
    }
};

pub const Instr = union(enum) {
    ret: Value,

    copy: Unary,
    jump: Identifier,
    jump_z: JumpIf,
    jump_nz: JumpIf,

    label: Identifier,

    unop_neg: Unary,
    unop_not: Unary,
    unop_lnot: Unary,

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

    func_call: struct {
        name: Identifier,
        args: std.ArrayListUnmanaged(Value),
        dst: Value,
    },

    fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        switch (self.*) {
            .func_call => |*f| f.args.deinit(alloc),
            else => {},
        }
    }

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
        target: Identifier,

        pub fn init(cond: Value, target: Identifier) @This() {
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

            .func_call => |f| {
                try writer.print("{} <- {}(", .{ f.dst, f.name });
                for (f.args.items, 0..) |arg, idx|
                    try writer.print("{s}{}", .{
                        if (idx > 0) ", " else "",
                        arg,
                    });
                try writer.writeByte(')');
            },
        }
    }
};

pub const Value = union(enum) {
    constant: i32,
    variable: Identifier,

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
