const std = @import("std");

pub const Prgm = struct {
    func_def: *FuncDef,
};

pub const FuncDef = struct {
    name: []const u8,
    body: *Stmt,
};

pub const Stmt = union(enum) {
    @"return": *Expr,
};

pub const Expr = union(enum) {
    constant: u64,
};
