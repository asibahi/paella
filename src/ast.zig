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
        try writer.writeByteNTimes('=', 32);
    }
};

pub const FuncDef = struct {
    name: []const u8,
    block: Block,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const w = options.width orelse 0;
        try writer.writeByteNTimes('\t', w);

        try writer.print("FUNCTION {s}\n", .{self.name});
        var iter = self.block.body.constIterator(0);
        while (iter.next()) |item|
            try writer.print("{:[1]}\n", .{
                item,
                w + 1,
            });
    }
};

pub const Block = struct {
    body: std.SegmentedList(BlockItem, 0),
};

pub const BlockItem = union(enum) {
    D: Decl,
    S: Stmt,

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

    pub inline fn stmt(s: Stmt) BlockItem {
        return .{ .S = s };
    }

    pub inline fn decl(d: Decl) BlockItem {
        return .{ .D = d };
    }
};

pub const Decl = struct {
    name: []const u8,
    init: ?*Expr,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const w = options.width orelse 0;
        try writer.writeByteNTimes('\t', w);

        try writer.print("int {s}", .{self.name});
        if (self.init) |e|
            try writer.print(" <- {}", .{e});
    }
};

pub const Stmt = union(enum) {
    @"return": *Expr,
    expr: *Expr,
    @"if": struct { cond: *Expr, then: *Stmt, @"else": ?*Stmt },
    compound: Block,
    @"break": ?[:0]const u8,
    @"continue": ?[:0]const u8,
    @"while": While,
    do_while: While,
    @"for": For,
    null: void,

    const While = struct {
        cond: *Expr,
        body: *Stmt,
        label: ?[:0]const u8,
    };

    pub const For = struct {
        label: ?[:0]const u8,
        init: Init,
        cond: ?*Expr,
        post: ?*Expr,
        body: *Stmt,

        pub const Init = union(enum) { decl: *Decl, expr: *Expr, none };
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
            .@"return" => |expr| try writer.print("RETURN {}", .{expr}),
            .expr => |expr| try writer.print("{};", .{expr}),
            .@"if" => |cs| {
                try writer.print("IF {}\n", .{cs.cond});
                try writer.print("{:^[1]}", .{ cs.then, w + 1 });
                if (cs.@"else") |es| {
                    try writer.writeByte('\n');
                    try writer.writeByteNTimes('\t', w);
                    try writer.writeAll("ELSE\n");
                    try writer.print("{:^[1]}", .{ es, w + 1 });
                }
            },
            .@"break" => |l| if (l) |label|
                try writer.print("BREAK :{s}", .{label})
            else
                try writer.writeAll("BREAK"),
            .@"continue" => |l| if (l) |label|
                try writer.print("CONTINUE :{s}", .{label})
            else
                try writer.writeAll("CONTINUE"),
            .@"while" => |wl| {
                if (wl.label) |label|
                    try writer.print("{s}: ", .{label});
                try writer.print("WHILE {}\n", .{wl.cond});
                try writer.print("{:^[1]}", .{ wl.body, w + 1 });
            },
            .do_while => |wl| {
                if (wl.label) |label|
                    try writer.print("{s}: ", .{label});
                try writer.print("UNTIL {}\n", .{wl.cond});
                try writer.print("{:^[1]}", .{ wl.body, w + 1 });
            },
            .@"for" => |f| {
                if (f.label) |label|
                    try writer.print("{s}: ", .{label});
                try writer.writeAll("FOR ");
                switch (f.init) {
                    .none => try writer.writeAll("---; "),
                    inline else => |data| try writer.print("{}; ", .{data}),
                }
                if (f.cond) |fc|
                    try writer.print("{}; ", .{fc})
                else
                    try writer.writeAll("---; ");
                if (f.post) |fp|
                    try writer.print("{}\n", .{fp})
                else
                    try writer.writeAll("---\n");

                try writer.print("{:^[1]}", .{ f.body, w + 1 });
            },
            .compound => |b| {
                var iter = b.body.constIterator(0);

                var cw: usize = undefined;
                if (options.alignment != .center) {
                    try writer.writeAll("DO");
                    cw = w + 1;
                } else {
                    if (iter.next()) |item|
                        try writer.print("{}", .{item});
                    cw = w;
                }

                while (iter.next()) |item| {
                    try writer.print("\n{:[1]}", .{
                        item,
                        cw,
                    });
                }
            },
            .null => try writer.print(";", .{}),
            // else => @panic("todo"),
        }
    }
};

pub const Expr = union(enum) {
    constant: u64,
    @"var": []const u8,
    assignment: BinOp,

    unop_neg: *Expr,
    unop_not: *Expr,
    unop_lnot: *Expr, // logical not

    binop_add: BinOp,
    binop_sub: BinOp,
    binop_mul: BinOp,
    binop_div: BinOp,
    binop_rem: BinOp,

    binop_and: BinOp,
    binop_or: BinOp,
    binop_eql: BinOp,
    binop_neq: BinOp,
    binop_lt: BinOp,
    binop_gt: BinOp,
    binop_le: BinOp,
    binop_ge: BinOp,

    ternary: struct { *Expr, *Expr, *Expr },

    pub const BinOp = struct { *Expr, *Expr };

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .constant => |c| try writer.print("{d}", .{c}),
            .@"var" => |s| try writer.print("{s}", .{s}),
            .assignment => |b| try writer.print("({} <- {})", b),
            // S-Expr
            .unop_neg => |e| try writer.print("(- {})", .{e}),
            .unop_not => |e| try writer.print("(~ {})", .{e}),
            .unop_lnot => |e| try writer.print("(! {})", .{e}),

            .binop_add => |b| try writer.print("(+ {} {})", b),
            .binop_sub => |b| try writer.print("(- {} {})", b),
            .binop_mul => |b| try writer.print("(* {} {})", b),
            .binop_div => |b| try writer.print("(/ {} {})", b),
            .binop_rem => |b| try writer.print("(% {} {})", b),

            .binop_and => |b| try writer.print("(&& {} {})", b),
            .binop_or => |b| try writer.print("(|| {} {})", b),
            .binop_eql => |b| try writer.print("(== {} {})", b),
            .binop_neq => |b| try writer.print("(!= {} {})", b),
            .binop_lt => |b| try writer.print("(< {} {})", b),
            .binop_gt => |b| try writer.print("(> {} {})", b),
            .binop_le => |b| try writer.print("(<= {} {})", b),
            .binop_ge => |b| try writer.print("(>= {} {})", b),

            .ternary => |t| try writer.print("(?: {} {} {})", t),
        }
    }
};
