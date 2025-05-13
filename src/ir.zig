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
    }
};

pub const FuncDef = struct {
    name: [:0]const u8,
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

        try writer.print("FUNCTION {s}\n", .{self.name});
        for (self.instrs.items) |instr|
            try writer.print("{:[1]}\n", .{
                instr,
                w + 1,
            });
    }
};

pub const Instr = union(enum) {
    ret: Value,
    unop_negate: Unary,
    unop_complement: Unary,

    pub const Unary = struct {
        src: Value,
        dst: Value,

        pub fn init(src: Value, dst: Value) @This() {
            return .{ .src = src, .dst = dst };
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
            .unop_negate => |u| try writer.print(
                "{[dst]} <- negate {[src]}",
                u,
            ),
            .unop_complement => |u| try writer.print(
                "{[dst]} <- complement {[src]}",
                u,
            ),
        }
    }
};

pub const Value = union(enum) {
    constant: u64,
    variable: [:0]const u8,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .constant => |c| try writer.print("{}", .{c}),
            .variable => |n| try writer.print("{s}", .{n}),
        }
    }
};
