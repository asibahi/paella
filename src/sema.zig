const std = @import("std");
const utils = @import("utils.zig");
const ast = @import("ast.zig");

pub fn resolve_prgm(
    gpa: std.mem.Allocator,
    strings: *utils.StringInterner,
    prgm: *ast.Prgm,
) Error!void {
    try resolve_func_def(gpa, strings, prgm.func_def);
}

fn resolve_func_def(
    gpa: std.mem.Allocator,
    strings: *utils.StringInterner,
    func_def: *ast.FuncDef,
) Error!void {
    var variable_map: std.StringHashMapUnmanaged(Entry) = .empty;
    defer variable_map.deinit(gpa);

    const bp: Boilerplate = .{
        .gpa = gpa,
        .strings = strings,
        .variable_map = &variable_map,
    };
    try resolve_block(bp, null, &func_def.block);
}

fn resolve_block(
    bp: Boilerplate,
    current_label: ?[:0]const u8,
    block: *ast.Block,
) Error!void {
    var iter = block.body.iterator(0);
    while (iter.next()) |item| switch (item.*) {
        .S => |*s| try resolve_stmt(bp, current_label, s),
        .D => |*d| try resolve_decl(bp, d),
    };
}

fn resolve_decl(
    bp: Boilerplate,
    decl: *ast.Decl,
) Error!void {
    if (bp.variable_map.get(decl.name)) |entry| if (entry.scope == .local)
        return error.DuplicateVariableDecl;

    const unique_name = try bp.make_temporary(decl.name);
    try bp.variable_map.put(bp.gpa, decl.name, .{ .name = unique_name });

    if (decl.init) |expr|
        try resolve_expr(bp, expr);
    decl.name = unique_name;
}

fn resolve_stmt(
    bp: Boilerplate,
    current_label: ?[:0]const u8,
    stmt: *ast.Stmt,
) Error!void {
    switch (stmt.*) {
        .null => {},
        .@"break", .@"continue" => |*l| l.* = current_label orelse
            return error.BreakOrContinueOutsideLoop,
        .@"return", .expr => |expr| try resolve_expr(bp, expr),
        .@"if" => |i| {
            try resolve_expr(bp, i.cond);
            try resolve_stmt(bp, current_label, i.then);
            if (i.@"else") |e|
                try resolve_stmt(bp, current_label, e);
        },
        .@"while", .do_while => |*w| {
            const label = try bp.make_temporary("while");
            w.label = label;
            try resolve_expr(bp, w.cond);
            try resolve_stmt(bp, label, w.body);
        },
        .@"for", .compound => {
            var variable_map = try bp.variable_map.clone(bp.gpa);
            defer variable_map.deinit(bp.gpa);

            var iter = variable_map.valueIterator();
            while (iter.next()) |value|
                value.* = .{ .name = value.name, .scope = .parent };

            const inner_bp: Boilerplate = .{
                .gpa = bp.gpa,
                .strings = bp.strings,
                .variable_map = &variable_map,
            };

            switch (stmt.*) {
                .compound => |*b| try resolve_block(inner_bp, current_label, b),
                .@"for" => |*f| {
                    const label = try bp.make_temporary("for");
                    f.label = label;
                    switch (f.init) {
                        .decl => |d| try resolve_decl(inner_bp, d),
                        .expr => |e| try resolve_expr(inner_bp, e),
                        .none => {},
                    }
                    if (f.cond) |c| try resolve_expr(inner_bp, c);
                    if (f.post) |p| try resolve_expr(inner_bp, p);
                    try resolve_stmt(inner_bp, label, f.body);
                },
                else => unreachable,
            }
        },
        // else => @panic("unimplemented"),
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
            .{ .@"var" = un.name }
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
    variable_map: *std.StringHashMapUnmanaged(Entry),

    fn make_temporary(
        self: @This(),
        prefix: []const u8,
    ) Error![:0]const u8 {
        return try self.strings.make_temporary(self.gpa, prefix);
    }
};

const Entry = struct {
    name: [:0]const u8,
    scope: enum { local, parent } = .local,
};

const Error = std.mem.Allocator.Error || std.fmt.BufPrintError ||
    error{
        DuplicateVariableDecl,
        InvalidLValue,
        UndeclaredVariable,
        BreakOrContinueOutsideLoop,
    };
