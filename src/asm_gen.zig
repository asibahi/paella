const std = @import("std");

const ast = @import("ast.zig");
const assembly = @import("assembly.zig");

pub fn prgm_to_asm(
    alloc: std.mem.Allocator,
    prgm: ast.Prgm,
) !assembly.Prgm {
    const func_def = try alloc.create(assembly.FuncDef);
    errdefer alloc.destroy(func_def);

    func_def.* = try func_def_to_asm(alloc, prgm.func_def.*);

    return .{ .func_def = func_def };
}

fn func_def_to_asm(
    alloc: std.mem.Allocator,
    func_def: ast.FuncDef,
) !assembly.FuncDef {
    const name = try alloc.dupe(u8, func_def.name);
    errdefer alloc.free(name);

    const instrs = try stmt_to_asm(alloc, func_def.body.*);

    return .{
        .name = name,
        .instrs = instrs,
    };
}

fn stmt_to_asm(
    alloc: std.mem.Allocator,
    stmt: ast.Stmt,
) !std.ArrayListUnmanaged(assembly.Inst) {
    switch (stmt) {
        .@"return" => |value| {
            var result: std.ArrayListUnmanaged(assembly.Inst) = .empty;
            try result.appendSlice(alloc, &.{
                .{ .mov = .init(
                    try expr_to_asm(alloc, value.*),
                    .reg,
                ) },

                .ret,
            });

            return result;
        },
    }
}

fn expr_to_asm(
    _: std.mem.Allocator,
    expr: ast.Expr,
) !assembly.Operand {
    switch (expr) {
        .constant => |i| return .{ .imm = i },
    }
}
