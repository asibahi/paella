const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

pub fn parse_prgm(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) !*ast.Prgm {
    const func_def = try parse_func_def(alloc, tokens);

    // now that we are done, check the tokenizer is emoty.
    if (tokens.next()) |_| return error.ExtraJunk;

    const ret = try alloc.create(ast.Prgm);
    ret.* = .{ .func_def = func_def };

    return ret;
}

fn parse_func_def(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) !*ast.FuncDef {
    try expect(.type_int, tokens);

    const name = try expect_ident(tokens);

    try expect(.l_paren, tokens);
    try expect(.keyword_void, tokens);
    try expect(.r_paren, tokens);

    try expect(.l_brace, tokens);
    const body = try parse_stmt(alloc, tokens);
    try expect(.r_brace, tokens);

    const ret = try alloc.create(ast.FuncDef);
    ret.* = .{ .name = name, .body = body };

    return ret;
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

            const ret = try alloc.create(ast.Expr);
            ret.* = .{ .constant = res };

            return ret;
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

    const ret = try alloc.create(ast.Stmt);
    ret.* = .{ .@"return" = expr };

    return ret;
}

fn expect(
    expected: lexer.Token.Tag,
    tokens: *lexer.Tokenizer,
) !void {
    if (tokens.next()) |actual| {
        if (actual.tag != expected)
            return error.SyntaxError;
    } else return error.SyntaxError;
}

fn expect_ident(
    tokens: *lexer.Tokenizer,
) ![]const u8 {
    if (tokens.next()) |actual| {
        if (actual.tag != .identifier)
            return error.SyntaxError;
        return tokens.buffer[actual.loc.start..actual.loc.end];
    } else return error.SyntaxError;
}
