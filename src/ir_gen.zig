const std = @import("std");

const ast = @import("ast.zig");
const ir = @import("ir.zig");

const utils = @import("utils.zig");

pub fn prgm_emit_it(
    alloc: std.mem.Allocator,
    interner: *utils.StringInterner,
    prgm: *ast.Prgm,
) !ir.Prgm {
    const func_def = try utils.create(
        ir.FuncDef,
        alloc,
        try func_def_emit_ir(alloc, interner, prgm.func_def),
    );

    return .{ .func_def = func_def };
}

fn func_def_emit_ir(
    alloc: std.mem.Allocator,
    interner: *utils.StringInterner,
    func_def: *ast.FuncDef,
) !ir.FuncDef {
    const name = try interner.get_or_put(alloc, func_def.name);

    var instrs: std.ArrayListUnmanaged(ir.Instr) = .empty;
    try stmy_emit_ir(alloc, interner, func_def.body, &instrs);

    return .{ .name = name.string, .instrs = instrs };
}

fn stmy_emit_ir(
    alloc: std.mem.Allocator,
    interner: *utils.StringInterner,
    stmt: *ast.Stmt,
    instrs: *std.ArrayListUnmanaged(ir.Instr),
) !void {
    switch (stmt.*) {
        .@"return" => |e| try instrs.append(alloc, .{
            .ret = try expr_emit_ir(alloc, interner, e, instrs),
        }),
    }
}

fn expr_emit_ir(
    alloc: std.mem.Allocator,
    interner: *utils.StringInterner,
    expr: *ast.Expr,
    instrs: *std.ArrayListUnmanaged(ir.Instr),
) !ir.Value {
    switch (expr.*) {
        .constant => |c| return .{ .constant = c },
        .unop_negate => |e| {
            const unary = try unary_helper(alloc, interner, e, instrs, "neg");
            try instrs.append(alloc, .{ .unop_negate = unary });
            return unary.dst;
        },
        .unop_complement => |e| {
            const unary = try unary_helper(alloc, interner, e, instrs, "cml");
            try instrs.append(alloc, .{ .unop_complement = unary });
            return unary.dst;
        },
    }
}

fn unary_helper(
    alloc: std.mem.Allocator,
    interner: *utils.StringInterner,
    expr: *ast.Expr,
    instrs: *std.ArrayListUnmanaged(ir.Instr),
    comptime prefix: []const u8,
) helper_error!ir.Instr.Unary {
    const src = expr_emit_ir(alloc, interner, expr, instrs) catch
        return error.UnaryHelper;
    const dst_name = try make_temporary(alloc, interner, prefix);
    const dst: ir.Value = .{ .variable = dst_name };

    return .init(src, dst);
}

fn make_temporary(
    alloc: std.mem.Allocator,
    interner: *utils.StringInterner,
    comptime prefix: []const u8,
) helper_error![:0]const u8 {

    // zig static variables
    const static = struct {
        var counter: usize = 0;
    };

    const name_alloc = std.fmt.allocPrint(
        alloc,
        if (prefix.len == 0) "tmp" else prefix ++ ".{}",
        .{static.counter},
    ) catch return error.MakeTemporary;
    defer alloc.free(name_alloc);

    const name = interner.get_or_put(alloc, name_alloc) catch
        return error.MakeTemporary;

    static.counter += 1;

    return name.string;
}

const helper_error = error{
    MakeTemporary,
    UnaryHelper,
};
