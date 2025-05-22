const std = @import("std");
const utils = @import("utils.zig");
const ast = @import("ast.zig");

pub fn resolve_prgm(
    gpa: std.mem.Allocator,
    strings: *utils.StringInterner,
    prgm: *ast.Prgm,
) Error!void {
    var variable_map: std.StringHashMapUnmanaged([:0]const u8) = .empty;
    defer variable_map.deinit(gpa);

    const bp: Boilerplate = .{
        .gpa = gpa,
        .strings = strings,
        .variable_map = &variable_map,
    };
    try resolve_func_def(bp, prgm.func_def);
}

fn resolve_func_def(
    bp: Boilerplate,
    func_def: *ast.FuncDef,
) Error!void {
    var iter = func_def.body.iterator(0);
    while (iter.next()) |item| switch (item.*) {
        .S => |*s| try resolve_stmt(bp, s),
        .D => |*d| try resolve_decl(bp, d),
    };
}

fn resolve_decl(
    bp: Boilerplate,
    decl: *ast.Decl,
) Error!void {
    if (bp.variable_map.contains(decl.name))
        return error.DuplicateVariableDecl;

    const unique_name = try bp.make_temporary(decl.name);
    try bp.variable_map.put(bp.gpa, decl.name, unique_name);

    if (decl.init) |expr|
        try resolve_expr(bp, expr);
    decl.name = unique_name;
}

fn resolve_stmt(
    bp: Boilerplate,
    stmt: *ast.Stmt,
) Error!void {
    switch (stmt.*) {
        .null => {},
        .@"return", .expr => |expr| try resolve_expr(bp, expr),
        .@"if" => |i| {
            try resolve_expr(bp, i.cond);
            try resolve_stmt(bp, i.then);
            if (i.@"else") |e|
                try resolve_stmt(bp, e);
        },
    }
}

fn resolve_expr(
    bp: Boilerplate,
    expr: *ast.Expr,
) Error!void {
    switch (expr.*) {
        .constant => {},
        .assignment => |*b| {
            if (b.@"0".* != .@"var") return error.InvalidLValue;
            try resolve_expr(bp, b.@"0");
            try resolve_expr(bp, b.@"1");
        },
        .@"var" => |name| expr.* = if (bp.variable_map.get(name)) |un|
            .{ .@"var" = un }
        else
            return error.UndeclaredVariable,
        .unop_neg,
        .unop_not,
        .unop_lnot,
        => |u| try resolve_expr(bp, u),
        .binop_add,
        .binop_sub,
        .binop_mul,
        .binop_div,
        .binop_rem,
        .binop_and,
        .binop_or,
        .binop_eql,
        .binop_neq,
        .binop_ge,
        .binop_gt,
        .binop_le,
        .binop_lt,
        => |b| {
            try resolve_expr(bp, b.@"0");
            try resolve_expr(bp, b.@"1");
        },
        .ternary => |t| {
            try resolve_expr(bp, t.@"0");
            try resolve_expr(bp, t.@"1");
            try resolve_expr(bp, t.@"2");
        },
    }
}

const Boilerplate = struct {
    gpa: std.mem.Allocator,
    strings: *utils.StringInterner,
    variable_map: *std.StringHashMapUnmanaged([:0]const u8),

    fn make_temporary(
        self: @This(),
        prefix: []const u8,
    ) Error![:0]const u8 {
        return try self.strings.make_temporary(self.gpa, prefix);
    }
};

const Error = std.mem.Allocator.Error || std.fmt.BufPrintError ||
    error{
        DuplicateVariableDecl,
        InvalidLValue,
        UndeclaredVariable,
    };
