const std = @import("std");

const ast = @import("ast.zig");
const ir = @import("ir.zig");

pub fn prgm_emit_it(
    alloc: std.mem.Allocator,
    prgm: *ast.Prgm,
) !ir.Prgm {
    const func_def = try func_def_emit_ir(alloc, prgm.func_def);
    return .{ .func_def = func_def };
}

fn func_def_emit_ir(
    alloc: std.mem.Allocator,
    func_def: *ast.FuncDef,
) !ir.FuncDef {
    const name = try alloc.dupe(u8, func_def.name);
    var instrs: std.ArrayListUnmanaged(ir.Instr) = .empty;

    try stmy_emit_ir(alloc, func_def.body, &instrs);

    return .{ .name = name, .instrs = instrs };
}

fn stmy_emit_ir(
    alloc: std.mem.Allocator,
    stmt: *ast.Stmt,
    instrs: *std.ArrayListUnmanaged(ir.Instr),
) !void {
    switch (stmt.*) {
        .@"return" => |e| try instrs.append(alloc, .{
            .ret = try expr_emit_ir(alloc, e, instrs),
        }),
    }
}

fn expr_emit_ir(
    alloc: std.mem.Allocator,
    expr: *ast.Expr,
    instrs: *std.ArrayListUnmanaged(ir.Instr),
) !ir.Value {
    switch (expr.*) {
        .constant => |c| return .{ .constant = c },
        .unop_negate => |e| {
            const src, const dst = try unary_helper(alloc, e, instrs, "neg");
            try instrs.append(alloc, .{ .unop_negate = .init(src, dst) });
            return dst;
        },
        .unop_complement => |e| {
            const src, const dst = try unary_helper(alloc, e, instrs, "cml");
            try instrs.append(alloc, .{ .unop_complement = .init(src, dst) });
            return dst;
        },
    }
}

fn unary_helper(
    alloc: std.mem.Allocator,
    expr: *ast.Expr,
    instrs: *std.ArrayListUnmanaged(ir.Instr),
    comptime prefix: []const u8,
) helper_error!struct { ir.Value, ir.Value } {
    const src = expr_emit_ir(alloc, expr, instrs) catch
        return error.UnaryHelper;
    const dst_name = try make_temporary(alloc, prefix);
    const dst: ir.Value = .{ .variable = dst_name };

    return .{ src, dst };
}

fn make_temporary(
    alloc: std.mem.Allocator,
    comptime prefix: []const u8,
) error{MakeTemporary}![]const u8 {

    // zig static variables
    const static = struct {
        var counter: usize = 0;
    };

    const name = std.fmt.allocPrint(
        alloc,
        if (prefix.len == 0) "temp" else prefix ++ ".{}",
        .{static.counter},
    ) catch return error.MakeTemporary;
    static.counter += 1;

    return name;
}

const helper_error = error{
    MakeTemporary,
    UnaryHelper,
};
