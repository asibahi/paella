const std = @import("std");
const utils = @import("utils.zig");
const ast = @import("ast.zig");

pub fn resolve_prgm(
    gpa: std.mem.Allocator,
    strings: *utils.StringInterner,
    prgm: *ast.Prgm,
) Error!void {
    var variable_map: VariableMap = .empty;
    defer variable_map.deinit(gpa);

    const bp: Boilerplate = .{
        .gpa = gpa,
        .strings = strings,
        .variable_map = &variable_map,
    };

    var iter = prgm.funcs.iterator(0);
    while (iter.next()) |item|
        try resolve_func_decl(bp, item);
}

fn resolve_func_decl(
    bp: Boilerplate,
    func_decl: *ast.FuncDecl,
) Error!void {
    if (bp.variable_map.get(func_decl.name)) |prev|
        if (prev.scope == .local and prev.linkage != .external)
            return error.DuplicateFunctionDecl;

    try bp.variable_map.put(bp.gpa, func_decl.name, .{
        .name = try bp.strings.get_or_put(bp.gpa, func_decl.name),
        .scope = .local,
        .linkage = .external,
    });

    var variable_map = try bp.variable_map.clone(bp.gpa);
    defer variable_map.deinit(bp.gpa);

    var iter = variable_map.valueIterator();
    while (iter.next()) |value|
        value.globalize();

    const inner_bp = bp.into_ineer(&variable_map);

    var params = func_decl.params.iterator(0);
    while (params.next()) |param| {
        if (inner_bp.variable_map.get(param.name)) |entry|
            if (entry.scope == .local)
                return error.DuplicateVariableDecl;

        const unique_name = try inner_bp.make_temporary(param.name);
        try inner_bp.variable_map.put(
            inner_bp.gpa,
            param.name,
            .{ .name = unique_name },
        );

        param.* = .{ .idx = unique_name };
    }

    if (func_decl.block) |*block|
        try resolve_block(inner_bp, null, block);
}

fn resolve_block(
    bp: Boilerplate,
    current_label: ?utils.StringInterner.Idx,
    block: *ast.Block,
) Error!void {
    var iter = block.body.iterator(0);
    while (iter.next()) |item| switch (item.*) {
        .S => |*s| try resolve_stmt(bp, current_label, s),
        .D => |*d| switch (d.*) {
            .F => |*f| if (f.block) |_|
                return error.IllegalFuncDefinition
            else
                try resolve_func_decl(bp, f),
            .V => |*v| try resolve_var_decl(bp, v),
        },
    };
}

fn resolve_var_decl(
    bp: Boilerplate,
    decl: *ast.VarDecl,
) Error!void {
    if (bp.variable_map.get(decl.name.name)) |entry| if (entry.scope == .local)
        return error.DuplicateVariableDecl;

    const unique_name = try bp.make_temporary(decl.name.name);
    try bp.variable_map.put(bp.gpa, decl.name.name, .{ .name = unique_name });

    if (decl.init) |expr|
        try resolve_expr(bp, expr);
    decl.name = .{ .idx = unique_name };
}

fn resolve_stmt(
    bp: Boilerplate,
    current_label: ?utils.StringInterner.Idx,
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
                value.globalize();

            const inner_bp = bp.into_ineer(&variable_map);

            switch (stmt.*) {
                .compound => |*b| try resolve_block(inner_bp, current_label, b),
                .@"for" => |*f| {
                    const label = try bp.make_temporary("for");
                    f.label = label;
                    switch (f.init) {
                        .decl => |d| try resolve_var_decl(inner_bp, d),
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
        .@"var" => |name| expr.* = if (bp.variable_map.get(name.name)) |un|
            .{ .@"var" = .{ .idx = un.name } }
        else
            return error.UndeclaredVariable,
        .func_call => |*f| if (bp.variable_map.get(f.@"0".name)) |entry| {
            f.@"0" = .{ .idx = entry.name };
            var iter = f.@"1".iterator(0);
            while (iter.next()) |item|
                try resolve_expr(bp, item);
        } else return error.UndeclaredFunction,
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

        // else => @panic("unimplemented"),
    }
}

const Boilerplate = struct {
    gpa: std.mem.Allocator,
    strings: *utils.StringInterner,
    variable_map: *VariableMap,

    fn make_temporary(
        self: @This(),
        prefix: []const u8,
    ) Error!utils.StringInterner.Idx {
        return try self.strings.make_temporary(self.gpa, prefix);
    }

    fn into_ineer(self: @This(), map: *VariableMap) @This() {
        return .{
            .gpa = self.gpa,
            .strings = self.strings,
            .variable_map = map,
        };
    }
};

const VariableMap = std.StringHashMapUnmanaged(
    Entry,
);

const Entry = struct {
    name: utils.StringInterner.Idx,
    scope: enum { local, parent } = .local,
    linkage: enum { none, external } = .none,

    fn globalize(self: *@This()) void {
        self.* = .{
            .name = self.name,
            .linkage = self.linkage,
            .scope = .parent,
        };
    }
};

const Error = std.mem.Allocator.Error || std.fmt.BufPrintError ||
    error{
        DuplicateVariableDecl,
        DuplicateFunctionDecl,
        InvalidLValue,
        UndeclaredVariable,
        UndeclaredFunction,
        BreakOrContinueOutsideLoop,
        IllegalFuncDefinition,
    };
