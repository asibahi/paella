const std = @import("std");
const utils = @import("utils.zig");
const ast = @import("ast.zig");

pub fn resolve_prgm(
    gpa: std.mem.Allocator,
    strings: *utils.StringInterner,
    prgm: *ast.Prgm,
) Error!TypeMap {
    var variable_map: VariableMap = .empty;
    defer variable_map.deinit(gpa);

    var type_map: TypeMap = .empty;

    const bp: Boilerplate = .{
        .gpa = gpa,
        .strings = strings,
        .variable_map = &variable_map,
        .type_map = &type_map,
    };

    var iter = prgm.decls.iterator(0);
    while (iter.next()) |item| switch (item.*) {
        .F => |*f| try resolve_func_decl(bp, f),
        .V => |*v| { // file scope variables
            const real_name = try strings.get_or_put(gpa, v.name.name);
            try variable_map.put(gpa, v.name.name, .{
                .name = real_name,
                .linkage = .has_linkage,
            });

            const init_value: Arrtibutes.Init = if (v.init) |e| switch (e.*) {
                .constant => |i| .{ .initial = i },
                else => return error.NonConstantInit,
            } else if (v.sc == .@"extern") .none else .tentative;

            const gop = try type_map.getOrPut(gpa, real_name.real_idx);
            if (gop.found_existing) {
                if (gop.value_ptr.* != .static)
                    return error.TypeError;

                gop.value_ptr.static.global = if (v.sc == .@"extern")
                    gop.value_ptr.static.global
                else if (gop.value_ptr.static.global != (v.sc != .static))
                    return error.ConflictingLinkage
                else
                    v.sc != .static;

                in: switch (gop.value_ptr.static.init) {
                    .initial => if (init_value == .initial)
                        return error.ConflictingDefinitions,
                    .tentative => if (init_value == .initial)
                        continue :in .none,
                    .none => gop.value_ptr.static.init = init_value,
                }
            } else gop.value_ptr.* = .{ .static = .{
                .init = init_value,
                .global = v.sc != .static,
            } };
        },
    };

    return type_map;
}

fn resolve_func_decl(
    bp: Boilerplate,
    func_decl: *ast.FuncDecl,
) Error!void {
    if (bp.variable_map.get(func_decl.name)) |prev|
        if (prev.scope == .local and prev.linkage == .none)
            return error.DuplicateDecl;

    const nname = try bp.strings.get_or_put(bp.gpa, func_decl.name);
    try bp.variable_map.put(bp.gpa, func_decl.name, .{
        .name = nname,
        .scope = .local,
        .linkage = .has_linkage,
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
            } else if (gop.value_ptr.func.global and
                func_decl.sc == .static)
            {
                return error.ConflictingFuncDecls;
            }
            gop.value_ptr.func.defined =
                gop.value_ptr.func.defined or func_decl.block != null;
        } else gop.value_ptr.* = .{ .func = .{
            .arity = func_decl.params.count(),
            .defined = func_decl.block != null,
            .global = func_decl.sc != .static,
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
        try resolve_local_var_decl(.param, inner_bp, param);

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
            else if (f.sc == .static)
                return error.TypeError
            else
                try resolve_func_decl(bp, f),
            .V => |*v| try resolve_local_var_decl(.@"var", bp, v),
        },
    };
}

fn resolve_local_var_decl(
    comptime T: enum { param, @"var" },
    bp: Boilerplate,
    item: switch (T) {
        .@"var" => *ast.VarDecl,
        .param => *ast.Identifier,
    },
) Error!void {
    const identifier, const sc: ast.StorageClass = switch (T) {
        .@"var" => .{ &item.name, item.sc },
        .param => .{ item, .none },
    };
    if (bp.variable_map.get(identifier.name)) |prev|
        if (prev.scope == .local)
            if (!(prev.linkage != .none and sc == .@"extern"))
                return error.DuplicateDecl;

    if (sc == .@"extern") {
        const nname = try bp.strings.get_or_put(bp.gpa, identifier.name);
        try bp.variable_map.put(bp.gpa, identifier.name, .{
            .name = nname,
            .linkage = .has_linkage,
        });
        { // TYPE CHECKING
            if (item.init != null) {
                return error.TypeError;
            }

            const gop = try bp.type_map.getOrPut(bp.gpa, nname.real_idx);
            if (gop.found_existing) {
                if (gop.value_ptr.* == .func)
                    return error.TypeError;
            } else gop.value_ptr.* = .{ .static = .{
                .init = .none,
                .global = true,
            } };
        }

        return;
    }

    const unique_name = try bp.make_temporary(identifier.name);
    try bp.variable_map.put(bp.gpa, identifier.name, .{ .name = unique_name });

    { // TYPE CHECKING
        const attr: Arrtibutes = if (sc == .static) ret: {
            const init_value: Arrtibutes.Init = if (item.init) |e| switch (e.*) {
                .constant => |i| .{ .initial = i },
                else => return error.TypeError,
            } else .{ .initial = 0 };

            break :ret .{ .static = .{
                .init = init_value,
                .global = false,
            } };
        } else .local;

        const gop = try bp.type_map.getOrPut(bp.gpa, unique_name.real_idx);
        if (gop.found_existing) {
            if (gop.value_ptr.* == .func)
                return error.TypeError;
        }
        gop.value_ptr.* = attr;
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
                        .decl => |d| try resolve_local_var_decl(.@"var", inner_bp, d),
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
            if (bp.type_map.get(un.name.real_idx).? != .func)
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
    linkage: enum { none, has_linkage } = .none,

    fn globalize(self: *@This()) void {
        self.* = .{
            .name = self.name,
            .linkage = self.linkage,
            .scope = .parent,
        };
    }
};

pub const TypeMap = std.AutoHashMapUnmanaged(
    u32,
    Arrtibutes,
);

pub const Arrtibutes = union(enum) {
    func: struct {
        arity: usize,
        defined: bool,
        global: bool,
    },
    static: struct {
        init: Init,
        global: bool,
    },
    local,

    const Init = union(enum) {
        tentative,
        initial: u64,
        none,
    };
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
        ConflictingFuncDecls,
        ConflictingLinkage,
        ConflictingDefinitions,
        NonConstantInit,
    };
