const std = @import("std");

pub const Prgm = struct {
    func_def: *FuncDef,

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
    name: []const u8,
    body: *Stmt,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const w = options.width orelse 0;
        try writer.writeByteNTimes('\t', w);

        try writer.print("FUNCTION {s}\n", .{self.name});
        try writer.print("{:[1]}", .{
            self.body,
            w + 1,
        });
    }
};

pub const Stmt = union(enum) {
    @"return": *Expr,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const w = options.width orelse 0;
        try writer.writeByteNTimes('\t', w);

        switch (self) {
            .@"return" => |expr| {
                try writer.print("RETURN {}", .{expr});
            },
        }
    }
};

pub const Expr = union(enum) {
    constant: u64,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .constant => |c| {
                try writer.print("{d}", .{c});
            },
        }
    }
};
