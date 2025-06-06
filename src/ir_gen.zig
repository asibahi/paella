const std = @import("std");
const ast = @import("ast.zig");
const ir = @import("ir.zig");
const sema = @import("sema.zig");
const utils = @import("utils.zig");

pub fn prgm_emit_ir(
    alloc: std.mem.Allocator,
    strings: *utils.StringInterner,
    type_map: *sema.TypeMap,
    prgm: *const ast.Prgm,
) Error!ir.Prgm {
    var top_level: std.ArrayListUnmanaged(ir.TopLevel) = try .initCapacity(
        alloc,
        prgm.decls.len,
    );

    { // FUNCTIONS
        var iter = prgm.decls.constIterator(0);
        while (iter.next()) |d| if (d.* == .F) if (d.F.block) |_| {
            var f_ir = try func_def_emit_ir(alloc, strings, &d.F);

            // assertions galore. so much hidden control flow
            f_ir.global = type_map.get(f_ir.name.real_idx).?.func.global;

            try top_level.append(alloc, .{ .F = f_ir });
        };
    }

    { // STATIC VARS
        var iter = type_map.iterator();
        while (iter.next()) |entry| if (entry.value_ptr.* == .static) {
            const name: utils.StringInterner.Idx = .{
                .real_idx = entry.key_ptr.*,
                .strings = strings,
            };
            const global = entry.value_ptr.static.global;
            const init = switch (entry.value_ptr.static.init) {
                .initial => |i| i,
                .tentative => 0,
                .none => continue,
            };
            try top_level.append(alloc, .{ .V = .{
                .name = name,
                .global = global,
                .init = init,
            } });
        };
    }

    return .{ .items = top_level, .type_map = type_map };
}

fn func_def_emit_ir(
    alloc: std.mem.Allocator,
    strings: *utils.StringInterner,
    func_def: *const ast.FuncDecl,
) Error!ir.FuncDef {
    const name = try strings.get_or_put(alloc, func_def.name);

    var params: std.ArrayListUnmanaged(utils.StringInterner.Idx) = try .initCapacity(
        alloc,
        func_def.params.count(),
    );
    var iter = func_def.params.constIterator(0);

    while (iter.next()) |param|
        try params.append(alloc, param.idx);

    var instrs: std.ArrayListUnmanaged(ir.Instr) = .empty;
    const bp: Boilerplate = .{
        .alloc = alloc,
        .strings = strings,
        .instrs = &instrs,
    };

    try block_emit_ir(bp, &func_def.block.?);
    try instrs.append(alloc, .{ .ret = .{ .constant = 0 } });

    return .{ .name = name, .params = params, .instrs = instrs };
}

fn block_emit_ir(
    bp: Boilerplate,
    block: *const ast.Block,
) Error!void {
    var iter = block.body.constIterator(0);
    while (iter.next()) |item| switch (item.*) {
        .S => |*s| try stmt_emit_ir(bp, s),
        .D => |d| if (d == .V) try var_decl_emit_ir(bp, &d.V),
    };
}

fn var_decl_emit_ir(
    bp: Boilerplate,
    decl: *const ast.VarDecl,
) Error!void {
    if (decl.sc == .none) if (decl.init) |e| {
        const src = try expr_emit_ir(bp, e);
        try bp.append(.{ .copy = .init(src, .{ .variable = decl.name.idx }) });
    };
}

fn stmt_emit_ir(
    bp: Boilerplate,
    stmt: *const ast.Stmt,
) Error!void {
    switch (stmt.*) {
        .null => {},
        .@"return" => |e| try bp.append(.{
            .ret = try expr_emit_ir(bp, e),
        }),
        .expr => |e| _ = try expr_emit_ir(bp, e),
        .@"if" => |c| {
            const cond = try expr_emit_ir(bp, c.cond);
            const else_label = try bp.make_temporary("else");
            try bp.append(.{ .jump_z = .{ .cond = cond, .target = else_label } });
            try stmt_emit_ir(bp, c.then);
            if (c.@"else") |@"else"| {
                const end_label = try bp.make_temporary("end");
                try bp.append(.{ .jump = end_label });
                try bp.append(.{ .label = else_label });
                try stmt_emit_ir(bp, @"else");
                try bp.append(.{ .label = end_label });
            } else try bp.append(.{ .label = else_label });
        },
        .compound => |b| try block_emit_ir(bp, &b),
        .do_while => |w| {
            const st = try bp.augment_label("st", w.label.?);
            const br = try bp.augment_label("br", w.label.?);
            const cn = try bp.augment_label("cn", w.label.?);

            try bp.append(.{ .label = st });
            try stmt_emit_ir(bp, w.body);
            try bp.append(.{ .label = cn });
            const v = try expr_emit_ir(bp, w.cond);
            try bp.append(.{ .jump_nz = .init(v, st) });
            try bp.append(.{ .label = br });
        },
        .@"while" => |w| {
            const br = try bp.augment_label("br", w.label.?);
            const cn = try bp.augment_label("cn", w.label.?);

            try bp.append(.{ .label = cn });
            const v = try expr_emit_ir(bp, w.cond);
            try bp.append(.{ .jump_z = .init(v, br) });
            try stmt_emit_ir(bp, w.body);
            try bp.append(.{ .jump = cn });
            try bp.append(.{ .label = br });
        },
        .@"for" => |f| {
            const st = try bp.augment_label("st", f.label.?);
            const br = try bp.augment_label("br", f.label.?);
            const cn = try bp.augment_label("cn", f.label.?);

            switch (f.init) {
                .decl => |d| try var_decl_emit_ir(bp, d),
                .expr => |e| _ = try expr_emit_ir(bp, e),
                .none => {},
            }
            try bp.append(.{ .label = st });
            if (f.cond) |c| {
                const v = try expr_emit_ir(bp, c);
                try bp.append(.{ .jump_z = .init(v, br) });
            }
            try stmt_emit_ir(bp, f.body);
            try bp.append(.{ .label = cn });
            if (f.post) |p|
                _ = try expr_emit_ir(bp, p);
            try bp.append(.{ .jump = st });
            try bp.append(.{ .label = br });
        },
        .@"break" => |l| try bp.append(.{
            .jump = try bp.augment_label("br", l.?),
        }),
        .@"continue" => |l| try bp.append(.{
            .jump = try bp.augment_label("cn", l.?),
        }),
        // else => @panic("todo"),
    }
}

fn expr_emit_ir(
    bp: Boilerplate,
    expr: *const ast.Expr,
) Error!ir.Value {
    switch (expr.*) {
        .constant => |c| return .{ .constant = c },
        .@"var" => |v| return .{ .variable = v.idx },
        .assignment => |b| {
            // bizarro order
            const dst = try expr_emit_ir(bp, b.@"0");
            const src = try expr_emit_ir(bp, b.@"1");
            try bp.append(.{ .copy = .init(src, dst) });
            return dst;
        },
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
        .unop_lnot => |e| {
            const unary = try bp.unary(e, "lnot");
            try bp.append(.{ .unop_lnot = unary });
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

        .binop_eql => |b| {
            const binary = try bp.binary(b, "eql");
            try bp.append(.{ .binop_eql = binary });
            return binary.dst;
        },
        .binop_neq => |b| {
            const binary = try bp.binary(b, "neq");
            try bp.append(.{ .binop_neq = binary });
            return binary.dst;
        },
        .binop_lt => |b| {
            const binary = try bp.binary(b, "lt");
            try bp.append(.{ .binop_lt = binary });
            return binary.dst;
        },
        .binop_le => |b| {
            const binary = try bp.binary(b, "le");
            try bp.append(.{ .binop_le = binary });
            return binary.dst;
        },
        .binop_gt => |b| {
            const binary = try bp.binary(b, "gt");
            try bp.append(.{ .binop_gt = binary });
            return binary.dst;
        },
        .binop_ge => |b| {
            const binary = try bp.binary(b, "ge");
            try bp.append(.{ .binop_ge = binary });
            return binary.dst;
        },

        .binop_and => |b| {
            const false_label = try bp.make_temporary("false_and");
            const end_label = try bp.make_temporary("end_and");
            const result = try bp.make_temporary("dst_and");

            const src1 = try expr_emit_ir(bp, b.@"0");
            try bp.append(.{ .jump_z = .init(src1, false_label) });
            const src2 = try expr_emit_ir(bp, b.@"1");
            try bp.append(.{ .jump_z = .init(src2, false_label) });
            const dst: ir.Value = .{ .variable = result };
            try bp.append(.{ .copy = .init(.{ .constant = 1 }, dst) });
            try bp.append(.{ .jump = end_label });
            try bp.append(.{ .label = false_label });
            try bp.append(.{ .copy = .init(.{ .constant = 0 }, dst) });
            try bp.append(.{ .label = end_label });

            return dst;
        },
        .binop_or => |b| {
            const true_label = try bp.make_temporary("true_or");
            const end_label = try bp.make_temporary("end_or");
            const result = try bp.make_temporary("dst_or");

            const src1 = try expr_emit_ir(bp, b.@"0");
            try bp.append(.{ .jump_nz = .init(src1, true_label) });
            const src2 = try expr_emit_ir(bp, b.@"1");
            try bp.append(.{ .jump_nz = .init(src2, true_label) });
            const dst: ir.Value = .{ .variable = result };
            try bp.append(.{ .copy = .init(.{ .constant = 0 }, dst) });
            try bp.append(.{ .jump = end_label });
            try bp.append(.{ .label = true_label });
            try bp.append(.{ .copy = .init(.{ .constant = 1 }, dst) });
            try bp.append(.{ .label = end_label });

            return dst;
        },
        .ternary => |t| {
            const else_label = try bp.make_temporary("else");
            const end_label = try bp.make_temporary("end");
            const dst_name = try bp.make_temporary("ter");
            const dst: ir.Value = .{ .variable = dst_name };

            const cond = try expr_emit_ir(bp, t.@"0");
            try bp.append(.{ .jump_z = .{ .cond = cond, .target = else_label } });
            const then = try expr_emit_ir(bp, t.@"1");
            try bp.append(.{ .copy = .init(then, dst) });

            try bp.append(.{ .jump = end_label });
            try bp.append(.{ .label = else_label });

            const else_ = try expr_emit_ir(bp, t.@"2");
            try bp.append(.{ .copy = .init(else_, dst) });

            try bp.append(.{ .label = end_label });

            return dst;
        },
        .func_call => |f| {
            var args: std.ArrayListUnmanaged(ir.Value) = try .initCapacity(
                bp.alloc,
                f.@"1".count(),
            );

            const dst: ir.Value = .{ .variable = try bp.make_temporary("fn") };

            var iter = f.@"1".constIterator(0);
            while (iter.next()) |e| {
                const v = try expr_emit_ir(bp, e);
                try args.append(bp.alloc, v);
            }

            try bp.append(.{ .func_call = .{
                .name = f.@"0".idx,
                .args = args,
                .dst = dst,
            } });

            return dst;
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

    fn make_temporary(
        self: @This(),
        comptime prefix: []const u8,
    ) Error!utils.StringInterner.Idx {
        return try self.strings.make_temporary(self.alloc, prefix);
    }

    fn augment_label(
        self: @This(),
        comptime prefix: []const u8,
        label: utils.StringInterner.Idx,
    ) Error!utils.StringInterner.Idx {
        const st_label = self.strings.get_string(label).?;
        const cat = try std.fmt.allocPrint(self.alloc, prefix ++ "_{s}", .{st_label});
        defer self.alloc.free(cat);

        const name = try self.strings.get_or_put(self.alloc, cat);

        return name;
    }

    fn unary(
        self: @This(),
        e: *ast.Expr,
        comptime prefix: []const u8,
    ) Error!ir.Instr.Unary {
        const src = try expr_emit_ir(self, e);
        const dst_name = try self.make_temporary(prefix);
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
        const dst_name = try self.make_temporary(prefix);
        const dst: ir.Value = .{ .variable = dst_name };

        return .init(src1, src2, dst);
    }
};

const Error = std.mem.Allocator.Error || std.fmt.BufPrintError;
