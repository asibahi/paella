const std = @import("std");

const ast = @import("ast.zig");
const ir = @import("ir.zig");

const utils = @import("utils.zig");

pub fn prgm_emit_it(
    alloc: std.mem.Allocator,
    strings: *utils.StringInterner,
    prgm: *ast.Prgm,
) Error!ir.Prgm {
    const func_def = try utils.create(
        ir.FuncDef,
        alloc,
        try func_def_emit_ir(alloc, strings, prgm.func_def),
    );

    return .{ .func_def = func_def };
}

fn func_def_emit_ir(
    alloc: std.mem.Allocator,
    strings: *utils.StringInterner,
    func_def: *ast.FuncDef,
) Error!ir.FuncDef {
    const name = try strings.get_or_put(alloc, func_def.name);

    var instrs: std.ArrayListUnmanaged(ir.Instr) = .empty;

    const bp: Boilerplate = .{
        .alloc = alloc,
        .strings = strings,
        .instrs = &instrs,
    };
    try stmt_emit_ir(bp, func_def.body);

    return .{ .name = name.string, .instrs = instrs };
}

fn stmt_emit_ir(
    bp: Boilerplate,
    stmt: *ast.Stmt,
) Error!void {
    switch (stmt.*) {
        .@"return" => |e| try bp.append(.{
            .ret = try expr_emit_ir(bp, e),
        }),
    }
}

fn expr_emit_ir(
    bp: Boilerplate,
    expr: *ast.Expr,
) Error!ir.Value {
    switch (expr.*) {
        .constant => |c| return .{ .constant = c },
        .unop_neg => |e| {
            const unary = try bp.unary(e, "neg");
            try bp.append(.{ .unop_neg = unary });
            return unary.dst;
        },
        .unop_not => |e| {
            const unary = try bp.unary(e, "not");
            try bp.append(.{ .unop_not = unary });
            return unary.dst;
        },
        .binop_add => |b| {
            const binary = try bp.binary(b, "add");
            try bp.append(.{ .binop_add = binary });
            return binary.dst;
        },
        .binop_sub => |b| {
            const binary = try bp.binary(b, "sub");
            try bp.append(.{ .binop_sub = binary });
            return binary.dst;
        },
        .binop_mul => |b| {
            const binary = try bp.binary(b, "mul");
            try bp.append(.{ .binop_mul = binary });
            return binary.dst;
        },
        .binop_div => |b| {
            const binary = try bp.binary(b, "div");
            try bp.append(.{ .binop_div = binary });
            return binary.dst;
        },
        .binop_rem => |b| {
            const binary = try bp.binary(b, "rem");
            try bp.append(.{ .binop_rem = binary });
            return binary.dst;
        },
        // else => @panic("todo"),
    }
}

const Boilerplate = struct {
    alloc: std.mem.Allocator,
    strings: *utils.StringInterner,
    instrs: *std.ArrayListUnmanaged(ir.Instr),

    fn append(
        self: @This(),
        instr: ir.Instr,
    ) Error!void {
        try self.instrs.append(self.alloc, instr);
    }

    fn unary(
        self: @This(),
        e: *ast.Expr,
        comptime prefix: []const u8,
    ) Error!ir.Instr.Unary {
        const src = try expr_emit_ir(self, e);
        const dst_name = try make_temporary(self.alloc, self.strings, prefix);
        const dst: ir.Value = .{ .variable = dst_name };

        return .init(src, dst);
    }

    fn binary(
        self: @This(),
        b: ast.Expr.BinOp,
        comptime prefix: []const u8,
    ) Error!ir.Instr.Binary {
        const src1 = try expr_emit_ir(self, b.@"0");
        const src2 = try expr_emit_ir(self, b.@"1");
        const dst_name = try make_temporary(self.alloc, self.strings, prefix);
        const dst: ir.Value = .{ .variable = dst_name };

        return .init(src1, src2, dst);
    }
};

fn make_temporary(
    alloc: std.mem.Allocator,
    strings: *utils.StringInterner,
    comptime prefix: []const u8,
) Error![:0]const u8 {

    // zig static variables
    const static = struct {
        var counter: usize = 0;
    };

    var buf: [16]u8 = undefined;
    const name_buf = try std.fmt.bufPrint(
        &buf,
        (if (prefix.len == 0) "tmp" else prefix) ++ ".{}",
        .{static.counter},
    );

    const name = try strings.get_or_put(alloc, name_buf);

    static.counter += 1;

    return name.string;
}

const Error =
    std.mem.Allocator.Error || std.fmt.BufPrintError;
