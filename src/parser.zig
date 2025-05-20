const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

const utils = @import("utils.zig");

pub fn parse_prgm(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.Prgm {
    const func_def = try parse_func_def(arena, tokens);
    const func_ptr = try utils.create(ast.FuncDef, arena, func_def);

    // now that we are done, check the tokenizer is emoty.
    if (tokens.next()) |_| return error.ExtraJunk;

    return .{ .func_def = func_ptr };
}

fn parse_func_def(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.FuncDef {
    try expect(.type_int, tokens);

    const name = try expect(.identifier, tokens);

    try expect(.l_paren, tokens);
    try expect(.keyword_void, tokens);
    try expect(.r_paren, tokens);

    try expect(.l_brace, tokens);

    var body: std.SegmentedList(ast.BlockItem, 0) = .{};

    while (tokens.next()) |next_token| {
        if (next_token.tag == .r_brace) break;
        tokens.put_back(next_token);

        const item = try parse_block_item(arena, tokens);
        try body.append(arena, item);
    } else return error.SyntaxError;

    return .{ .name = name, .body = body };
}

fn parse_block_item(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.BlockItem {
    const next_token = tokens.next() orelse
        return error.SyntaxError;

    switch (next_token.tag) {
        .type_int => {
            const name = try expect(.identifier, tokens);
            const new_token = tokens.next() orelse
                return error.SyntaxError;

            const expr: ?*ast.Expr = switch (new_token.tag) {
                .equals => ret: {
                    const res = try parse_expr(arena, tokens, 0);
                    const expr_ptr = try utils.create(ast.Expr, arena, res);

                    try expect(.semicolon, tokens);
                    break :ret expr_ptr;
                },
                .semicolon => null,
                else => return error.SyntaxError,
            };

            return .{ .D = .{ .name = name, .expr = expr } };
        },
        // statements
        .semicolon => return .{ .S = .null },
        .keyword_return => {
            const expr = try parse_expr(arena, tokens, 0);
            const expr_ptr = try utils.create(ast.Expr, arena, expr);
            try expect(.semicolon, tokens);
            return .{ .S = .{ .@"return" = expr_ptr } };
        },
        else => {
            tokens.put_back(next_token);
            const expr = try parse_expr(arena, tokens, 0);
            const expr_ptr = try utils.create(ast.Expr, arena, expr);
            try expect(.semicolon, tokens);
            return .{ .S = .{ .expr = expr_ptr } };
        },
    }
}

fn parse_expr(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
    min_prec: u8,
) Error!ast.Expr {
    var lhs = try parse_factor(arena, tokens);

    var next_token = tokens.next() orelse
        return error.SyntaxError;
    defer tokens.put_back(next_token);

    while (next_token.tag.binop_precedence()) |r| {
        const prec, const left = r;
        if (prec < min_prec) break;

        const lhs_ptr = try utils.create(ast.Expr, arena, lhs);
        const rhs = try parse_expr(arena, tokens, prec + left);
        const rhs_ptr = try utils.create(ast.Expr, arena, rhs);

        const bin_op: ast.Expr.BinOp = .{ lhs_ptr, rhs_ptr };
        lhs = switch (next_token.tag) {
            .plus => .{ .binop_add = bin_op },
            .hyphen => .{ .binop_sub = bin_op },
            .asterisk => .{ .binop_mul = bin_op },
            .f_slash => .{ .binop_div = bin_op },
            .percent => .{ .binop_rem = bin_op },

            .equals => .{ .assignment = bin_op },

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

        next_token = tokens.next() orelse
            return error.SyntaxError;
    }

    return lhs;
}

fn parse_factor(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.Expr {
    const current = tokens.next() orelse
        return error.SyntaxError;

    switch (current.tag) {
        .identifier => return .{
            .@"var" = tokens.buffer[current.loc.start..current.loc.end],
        },
        .number_literal => {
            const lit = tokens.buffer[current.loc.start..current.loc.end];
            const res = std.fmt.parseInt(u64, lit, 10) catch
                return error.InvalidInt;

            return .{ .constant = res };
        },
        .hyphen => {
            const inner_exp = try parse_factor(arena, tokens);
            return .{ .unop_neg = try utils.create(ast.Expr, arena, inner_exp) };
        },
        .tilde => {
            const inner_exp = try parse_factor(arena, tokens);
            return .{ .unop_not = try utils.create(ast.Expr, arena, inner_exp) };
        },
        .bang => {
            const inner_exp = try parse_factor(arena, tokens);
            return .{ .unop_lnot = try utils.create(ast.Expr, arena, inner_exp) };
        },
        .l_paren => {
            const inner_exp = try parse_expr(arena, tokens, 0);
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
    try testing_prec("3 * 4 + 5", "(+ (* 3 4) 5)", .binop_add);
    try testing_prec(
        "4 + 3 && -17 * 4 < 5",
        "(&& (+ 4 3) (< (* (- 17) 4) 5))",
        .binop_and,
    );
    try testing_prec(
        "c = a / 6 + !b",
        "c <- (+ (/ a 6) (! b))",
        .assignment,
    );
    try testing_prec(
        "c * 2 == a - 1431655762",
        "(== (* c 2) (- a 1431655762))",
        .binop_eql,
    );
}

fn testing_prec(
    comptime src: [:0]const u8,
    comptime sexpr: []const u8,
    comptime expected: @typeInfo(ast.Expr).@"union".tag_type.?,
) !void {
    const t = std.testing;

    var a = std.heap.ArenaAllocator.init(t.allocator);
    defer a.deinit();

    var tokens = lexer.Tokenizer.init(src ++ ";");
    const result = try parse_expr(a.allocator(), &tokens, 0);

    try t.expect(result == expected);
    try t.expectFmt(sexpr, "{}", .{result});
}
