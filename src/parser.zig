const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

const utils = @import("utils.zig");

pub fn parse_prgm(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!*ast.Prgm {
    const func_def = try parse_func_def(alloc, tokens);

    // now that we are done, check the tokenizer is emoty.
    if (tokens.next()) |_| return error.ExtraJunk;

    return try utils.create(ast.Prgm, alloc, .{ .func_def = func_def });
}

fn parse_func_def(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!*ast.FuncDef {
    try expect(.type_int, tokens);

    const name = try expect(.identifier, tokens);

    try expect(.l_paren, tokens);
    try expect(.keyword_void, tokens);
    try expect(.r_paren, tokens);

    try expect(.l_brace, tokens);
    const body = try parse_stmt(alloc, tokens);
    try expect(.r_brace, tokens);

    return try utils.create(ast.FuncDef, alloc, .{ .name = name, .body = body });
}

fn parse_stmt(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!*ast.Stmt {
    try expect(.keyword_return, tokens);
    const expr = try parse_expr(alloc, tokens, 0);
    try expect(.semicolon, tokens);

    return try utils.create(ast.Stmt, alloc, .{ .@"return" = expr });
}

fn parse_expr(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
    min_prec: u8,
) Error!*ast.Expr {
    var lhs = try parse_factor(alloc, tokens);

    var next_token = tokens.next() orelse
        return error.SyntaxError;

    while (next_token.tag.binop_precedence()) |prec| {
        if (prec < min_prec) break;

        const rhs = try parse_expr(alloc, tokens, prec + 1);
        const bin_op: ast.Expr.BinOp = .{ lhs, rhs };
        const new_lhs: ast.Expr = switch (next_token.tag) {
            .plus => .{ .binop_add = bin_op },
            .hyphen => .{ .binop_sub = bin_op },
            .asterisk => .{ .binop_mul = bin_op },
            .f_slash => .{ .binop_div = bin_op },
            .percent => .{ .binop_rem = bin_op },

            .double_ambersand => .{ .binop_and = bin_op },
            .double_pipe => .{ .binop_or = bin_op },
            .double_equals => .{ .binop_eql = bin_op },
            .bang_equals => .{ .binop_neq = bin_op },
            .lesser_than => .{ .binop_lt = bin_op },
            .greater_than => .{ .binop_gt = bin_op },
            .lesser_equals => .{ .binop_le = bin_op },
            .greater_equals => .{ .binop_ge = bin_op },

            else => unreachable,
        };
        lhs = try utils.create(ast.Expr, alloc, new_lhs);
        next_token = tokens.next() orelse
            return error.SyntaxError;
    }

    tokens.put_back(next_token);
    return lhs;
}

fn parse_factor(
    alloc: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!*ast.Expr {
    const current = tokens.next() orelse
        return error.SyntaxError;

    switch (current.tag) {
        .number_literal => {
            const lit = tokens.buffer[current.loc.start..current.loc.end];
            const res = std.fmt.parseInt(u64, lit, 10) catch
                return error.InvalidInt;

            return try utils.create(ast.Expr, alloc, .{ .constant = res });
        },
        .hyphen => {
            const inner_exp = try parse_factor(alloc, tokens);
            return try utils.create(ast.Expr, alloc, .{ .unop_neg = inner_exp });
        },
        .tilde => {
            const inner_exp = try parse_factor(alloc, tokens);
            return try utils.create(ast.Expr, alloc, .{ .unop_not = inner_exp });
        },
        .bang => {
            const inner_exp = try parse_factor(alloc, tokens);
            return try utils.create(ast.Expr, alloc, .{ .unop_lnot = inner_exp });
        },
        .l_paren => {
            const inner_exp = try parse_expr(alloc, tokens, 0);
            try expect(.r_paren, tokens);

            return inner_exp;
        },
        else => return error.SyntaxError,
    }
}

inline fn expect(
    comptime expected: lexer.Token.Tag,
    tokens: *lexer.Tokenizer,
) Error!ExpectResult(expected) {
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

const Error =
    std.mem.Allocator.Error ||
    error{
        SyntaxError,
        InvalidInt,
        ExtraJunk,
    };

test "precedence" {
    const t = std.testing;

    var a_a = std.heap.ArenaAllocator.init(t.allocator);
    defer a_a.deinit();
    const a = a_a.allocator();

    {
        const src = "3 * 4 + 5;";
        var tokens = lexer.Tokenizer.init(src);
        const result = try parse_expr(a, &tokens, 0);

        try t.expect(result.* == .binop_add);
        try t.expectFmt("(+ (* 3 4) 5)", "{}", .{result});
    }
    {
        const src = "4 + 3 && -17 * 4 < 5;";
        var tokens = lexer.Tokenizer.init(src);
        const result = try parse_expr(a, &tokens, 0);

        try t.expect(result.* == .binop_and);
        try t.expectFmt("(&& (+ 4 3) (< (* (- 17) 4) 5))", "{}", .{result});
    }
}
