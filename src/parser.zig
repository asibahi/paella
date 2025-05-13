const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

const create = @import("utils.zig").create;

pub fn parse_prgm(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) !*ast.Prgm {
    const func_def = try parse_func_def(alloc, tokens);

    // now that we are done, check the tokenizer is emoty.
    if (tokens.next()) |_| return error.ExtraJunk;

    return try create(ast.Prgm, alloc, .{ .func_def = func_def });
}

fn parse_func_def(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) !*ast.FuncDef {
    try expect(.type_int, tokens);

    const name = try expect(.identifier, tokens);

    try expect(.l_paren, tokens);
    try expect(.keyword_void, tokens);
    try expect(.r_paren, tokens);

    try expect(.l_brace, tokens);
    const body = try parse_stmt(alloc, tokens);
    try expect(.r_brace, tokens);

    return try create(ast.FuncDef, alloc, .{ .name = name, .body = body });
}

fn parse_expr(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) !*ast.Expr {
    const current = tokens.next() orelse
        return error.ExpectExpr;

    switch (current.tag) {
        .number_literal => {
            const lit = tokens.buffer[current.loc.start..current.loc.end];
            const res = try std.fmt.parseInt(u64, lit, 10);

            return try create(ast.Expr, alloc, .{ .constant = res });
        },
        .hyphen => {
            const inner_exp = try parse_expr(alloc, tokens);
            return try create(ast.Expr, alloc, .{ .unop_negate = inner_exp });
        },
        .tilde => {
            const inner_exp = try parse_expr(alloc, tokens);
            return try create(ast.Expr, alloc, .{ .unop_complement = inner_exp });
        },
        .l_paren => {
            const inner_exp = try parse_expr(alloc, tokens);
            try expect(.r_paren, tokens);

            return inner_exp;
        },
        else => return error.ExpectExpr,
    }
}

fn parse_stmt(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) !*ast.Stmt {
    try expect(.keyword_return, tokens);
    const expr = try parse_expr(alloc, tokens);
    try expect(.semicolon, tokens);

    return try create(ast.Stmt, alloc, .{ .@"return" = expr });
}

inline fn expect(
    comptime expected: lexer.Token.Tag,
    tokens: *lexer.Tokenizer,
) !ExpectResult(expected) {
    if (tokens.next()) |actual| {
        if (actual.tag != expected)
            return error.SyntaxError;
        switch (expected) {
            .identifier => return tokens.buffer[actual.loc.start..actual.loc.end],
            else => {},
        }
    } else return error.SyntaxError;
}

fn ExpectResult(comptime expected: lexer.Token.Tag) type {
    switch (expected) {
        .identifier => return []const u8,
        else => return void,
    }
}
