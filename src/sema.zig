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

    var type_map: TypeMap = .empty;
    defer type_map.deinit(gpa);

    const bp: Boilerplate = .{
        .gpa = gpa,
        .strings = strings,
        .variable_map = &variable_map,
        .type_map = &type_map,
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
            return error.DuplicateDecl;

    const nname = try bp.strings.get_or_put(bp.gpa, func_decl.name);
    try bp.variable_map.put(bp.gpa, func_decl.name, .{
        .name = nname,
        .scope = .local,
        .linkage = .external,
    });
    {
        const gop = try bp.type_map.getOrPut(bp.gpa, nname.real_idx);
        if (gop.found_existing) {
            if (gop.value_ptr.* != .func or
                gop.value_ptr.func.arity != func_decl.params.count())
            {
                return error.TypeError;
            } else if (gop.value_ptr.func.defined and
                func_decl.block != null)
            {
                return error.DuplicateFunctionDef;
            }
        } else gop.value_ptr.* = .{ .func = .{
            .arity = func_decl.params.count(),
            .defined = func_decl.block != null,
        } };
    }
    // func_decl.name = .{ .idx = nname };

    var variable_map = try bp.variable_map.clone(bp.gpa);
    defer variable_map.deinit(bp.gpa);

    var iter = variable_map.valueIterator();
    while (iter.next()) |value|
        value.globalize();

    const inner_bp = bp.into_ineer(&variable_map);

    var params = func_decl.params.iterator(0);
    while (params.next()) |param|
        try resolve_var_decl(.param, inner_bp, param);

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
            .V => |*v| try resolve_var_decl(.@"var", bp, v),
        },
    };
}

fn resolve_var_decl(
    comptime T: enum { param, @"var" },
    bp: Boilerplate,
    item: switch (T) {
        .@"var" => *ast.VarDecl,
        .param => *ast.Identifier,
    },
) Error!void {
    const identifier = switch (T) {
        .@"var" => &item.name,
        .param => item,
    };
    if (bp.variable_map.get(identifier.name)) |entry| if (entry.scope == .local)
        return error.DuplicateDecl;

    const unique_name = try bp.make_temporary(identifier.name);
    try bp.variable_map.put(bp.gpa, identifier.name, .{ .name = unique_name });

    { // TYPE CHECKING
        const gop = try bp.type_map.getOrPut(bp.gpa, unique_name.real_idx);
        if (gop.found_existing) {
            if (gop.value_ptr.* != .int)
                return error.TypeError;
        } else gop.value_ptr.* = .int;
    }

    identifier.* = .{ .idx = unique_name };

    if (T == .@"var")
        if (item.init) |expr|
            try resolve_expr(bp, expr);
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
                        .decl => |d| try resolve_var_decl(.@"var", inner_bp, d),
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
        .@"var" => |name| if (bp.variable_map.get(name.name)) |un| {
            if (bp.type_map.get(un.name.real_idx).? == .int)
                expr.* = .{ .@"var" = .{ .idx = un.name } }
            else
                return error.TypeError;
        } else return error.UndeclaredVariable,

        .func_call => |*f| if (bp.variable_map.get(f.@"0".name)) |entry| {
            const t = bp.type_map.get(entry.name.real_idx).?;
            if (t == .func and
                t.func.arity == f.@"1".count())
            {
                f.@"0" = .{ .idx = entry.name };
                var iter = f.@"1".iterator(0);
                while (iter.next()) |item|
                    try resolve_expr(bp, item);
            } else return error.TypeError;
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
    type_map: *TypeMap,

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
            .type_map = self.type_map,
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

const TypeMap = std.AutoHashMapUnmanaged(
    u32,
    Type,
);

const Type = union(enum) {
    int,
    func: struct {
        arity: usize,
        defined: bool,
    },
};

const Error = std.mem.Allocator.Error || std.fmt.BufPrintError ||
    error{
        DuplicateDecl,
        DuplicateFunctionDef,
        InvalidLValue,
        TypeError,
        UndeclaredVariable,
        UndeclaredFunction,
        BreakOrContinueOutsideLoop,
        IllegalFuncDefinition,
    };
