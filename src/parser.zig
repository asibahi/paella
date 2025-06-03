const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

const utils = @import("utils.zig");

pub fn parse_prgm(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.Prgm {
    var decls: std.SegmentedList(ast.Decl, 0) = .{};

    while (tokens.next()) |next_token| {
        tokens.put_back(next_token);
        const decl = try parse_decl(.either, arena, tokens, .no);
        try decls.append(arena, decl);
    }

    return .{ .decls = decls };
}

fn parse_block(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.Block {
    try expect(.l_brace, tokens);

    var body: std.SegmentedList(ast.BlockItem, 0) = .{};

    while (tokens.next()) |next_token| {
        if (next_token.tag == .r_brace) break;
        tokens.put_back(next_token);

        const item = try parse_block_item(arena, tokens);
        try body.append(arena, item);
    } else return error.NotEnoughJunk;

    return .{ .body = body };
}

fn parse_block_item(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.BlockItem {
    if (parse_storage_class(tokens)) |sc|
        return .decl(try parse_decl(.either, arena, tokens, .{ .yes = sc }))
    else |_|
        return .stmt(try parse_stmt(arena, tokens));
}

fn parse_storage_class(
    tokens: *lexer.Tokenizer,
) Error!?ast.StorageClass {
    var type_seen = false;
    var sc: ?ast.StorageClass = null;

    while (tokens.next()) |nt| switch (nt.tag) {
        .type_int => type_seen = true,
        .keyword_static => sc = if (sc == null)
            .static
        else
            return error.InvalidStorageClass,
        .keyword_extern => sc = if (sc == null)
            .@"extern"
        else
            return error.InvalidStorageClass,
        else => {
            tokens.put_back(nt);
            break;
        },
    } else return error.NotEnoughJunk;

    if (!type_seen) return error.InvalidTypeSpecifier;
    return sc;
}

fn parse_decl(
    comptime ty: enum { @"var", either },
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
    parsed: union(enum) { yes: ?ast.StorageClass, no },
) Error!ast.Decl {
    const sc = if (parsed == .yes) parsed.yes else try parse_storage_class(tokens);
    const name = try expect(.identifier, tokens);

    const new_token = try tokens.next_force();

    switch (new_token.tag) {
        .semicolon => return .{ .V = .{
            .sc = sc,
            .name = .{ .name = name },
            .init = null,
        } },
        .equals => {
            const expr = try parse_expr(arena, tokens, 0);
            const expr_ptr = try utils.create(arena, expr);

            try expect(.semicolon, tokens);
            return .{ .V = .{
                .sc = sc,
                .name = .{ .name = name },
                .init = expr_ptr,
            } };
        },
        .l_paren => {
            if (ty == .@"var") return error.SyntaxError;
            var params: std.SegmentedList(ast.Identifier, 0) = .{};

            const param_peek = try tokens.next_force();
            params: switch (param_peek.tag) {
                .keyword_void => try expect(.r_paren, tokens),
                .type_int => {
                    const ident = try expect(.identifier, tokens);
                    try params.append(arena, .{ .name = ident });
                    const inner_param_peek = try tokens.next_force();
                    switch (inner_param_peek.tag) {
                        .comma => {
                            try expect(.type_int, tokens);
                            continue :params .type_int;
                        },
                        .r_paren => {},
                        else => continue :params .invalid,
                    }
                },
                else => return error.SyntaxError,
            }

            const block_peek = try tokens.next_force();
            const block = block: switch (block_peek.tag) {
                .semicolon => null,
                .l_brace => {
                    tokens.put_back(block_peek);
                    break :block try parse_block(arena, tokens);
                },
                else => return error.SyntaxError,
            };

            return .{ .F = .{
                .sc = sc,
                .name = name,
                .params = params,
                .block = block,
            } };
        },
        else => return error.SyntaxError,
    }
}

fn parse_stmt(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.Stmt {
    const current = try tokens.next_force();
    switch (current.tag) {
        .semicolon => return .null,
        .keyword_return => {
            const expr = try parse_expr(arena, tokens, 0);
            const expr_ptr = try utils.create(arena, expr);
            try expect(.semicolon, tokens);
            return .{ .@"return" = expr_ptr };
        },
        .keyword_if => {
            try expect(.l_paren, tokens);
            const cond = try parse_expr(arena, tokens, 0);
            const cond_ptr = try utils.create(arena, cond);
            try expect(.r_paren, tokens);

            const then = try parse_stmt(arena, tokens);
            const then_ptr = try utils.create(arena, then);

            const peek = try tokens.next_force();
            const else_ptr: ?*ast.Stmt = if (peek.tag == .keyword_else) s: {
                const e = try parse_stmt(arena, tokens);
                break :s try utils.create(arena, e);
            } else n: {
                tokens.put_back(peek);
                break :n null;
            };

            return .{ .@"if" = .{
                .cond = cond_ptr,
                .then = then_ptr,
                .@"else" = else_ptr,
            } };
        },

        .keyword_break => {
            try expect(.semicolon, tokens);
            return .{ .@"break" = null };
        },
        .keyword_continue => {
            try expect(.semicolon, tokens);
            return .{ .@"continue" = null };
        },

        .keyword_while => {
            try expect(.l_paren, tokens);
            const cond = try parse_expr(arena, tokens, 0);
            const cond_ptr = try utils.create(arena, cond);
            try expect(.r_paren, tokens);

            const body = try parse_stmt(arena, tokens);
            const body_ptr = try utils.create(arena, body);

            return .{ .@"while" = .{
                .cond = cond_ptr,
                .body = body_ptr,
                .label = null,
            } };
        },
        .keyword_do => {
            const body = try parse_stmt(arena, tokens);
            const body_ptr = try utils.create(arena, body);

            try expect(.keyword_while, tokens);
            try expect(.l_paren, tokens);
            const cond = try parse_expr(arena, tokens, 0);
            const cond_ptr = try utils.create(arena, cond);
            try expect(.r_paren, tokens);
            try expect(.semicolon, tokens);

            return .{ .do_while = .{
                .cond = cond_ptr,
                .body = body_ptr,
                .label = null,
            } };
        },
        .keyword_for => {
            try expect(.l_paren, tokens);

            const init: ast.Stmt.For.Init = init: {
                const peeked = try tokens.next_force();
                if (peeked.tag == .semicolon) break :init .none else {
                    tokens.put_back(peeked);
                    if (parse_storage_class(tokens)) |sc| {
                        if (sc != null) return error.SyntaxError;
                        const decl = try parse_decl(
                            .@"var",
                            arena,
                            tokens,
                            .{ .yes = sc },
                        );
                        const decl_ptr = try utils.create(arena, decl.V);
                        break :init .{ .decl = decl_ptr };
                    } else |_| { // <-- parse_sc already puts back any other token
                        const expr = try parse_expr(arena, tokens, 0);
                        const expr_ptr = try utils.create(arena, expr);
                        try expect(.semicolon, tokens);
                        break :init .{ .expr = expr_ptr };
                    }
                }
            };
            const cond: ?*ast.Expr = cond: {
                const peeked = try tokens.next_force();
                switch (peeked.tag) {
                    .semicolon => break :cond null,
                    else => {
                        tokens.put_back(peeked);
                        const expr = try parse_expr(arena, tokens, 0);
                        const expr_ptr = try utils.create(arena, expr);
                        try expect(.semicolon, tokens);
                        break :cond expr_ptr;
                    },
                }
            };
            const post: ?*ast.Expr = post: {
                const peeked = try tokens.next_force();
                switch (peeked.tag) {
                    .r_paren => break :post null,
                    else => {
                        tokens.put_back(peeked);
                        const expr = try parse_expr(arena, tokens, 0);
                        const expr_ptr = try utils.create(arena, expr);
                        try expect(.r_paren, tokens);
                        break :post expr_ptr;
                    },
                }
            };

            const body = try parse_stmt(arena, tokens);
            const body_ptr = try utils.create(arena, body);

            return .{ .@"for" = .{
                .init = init,
                .cond = cond,
                .post = post,
                .body = body_ptr,
                .label = null,
            } };
        },

        .l_brace => {
            tokens.put_back(current);
            const block = try parse_block(arena, tokens);

            return .{ .compound = block };
        },
        else => {
            tokens.put_back(current);
            const expr = try parse_expr(arena, tokens, 0);
            const expr_ptr = try utils.create(arena, expr);
            try expect(.semicolon, tokens);
            return .{ .expr = expr_ptr };
        },
    }
}

fn parse_expr(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
    min_prec: u8,
) Error!ast.Expr {
    var lhs = try parse_factor(arena, tokens);

    var current = try tokens.next_force();
    defer tokens.put_back(current);

    while (current.tag.binop_precedence()) |r| {
        const prec, const left = r;
        if (prec < min_prec) break;

        const lhs_ptr = try utils.create(arena, lhs);
        const then_ptr: ?*ast.Expr = if (current.tag == .query) t: {
            const then = try parse_expr(arena, tokens, 0);
            try expect(.colon, tokens);

            break :t try utils.create(arena, then);
        } else null;

        const rhs = try parse_expr(arena, tokens, if (left) prec + 1 else prec);
        const rhs_ptr = try utils.create(arena, rhs);

        const bin_op: ast.Expr.BinOp = .{ lhs_ptr, rhs_ptr };
        lhs = switch (current.tag) {
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

            .query => .{ .ternary = .{ lhs_ptr, then_ptr.?, rhs_ptr } },

            else => unreachable,
        };

        current = try tokens.next_force();
    }

    return lhs;
}

fn parse_factor(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!ast.Expr {
    const current = try tokens.next_force();

    switch (current.tag) {
        .identifier => {
            const next_token = try tokens.next_force();
            const name = tokens.buffer[current.loc.start..current.loc.end];

            switch (next_token.tag) {
                .l_paren => return .{ .func_call = .{
                    .{ .name = name },
                    try parse_args(arena, tokens),
                } },
                else => {
                    tokens.put_back(next_token);
                    return .{ .@"var" = .{ .name = name } };
                },
            }
        },
        .number_literal => {
            const lit = tokens.buffer[current.loc.start..current.loc.end];
            const res = std.fmt.parseInt(u64, lit, 10) catch
                return error.InvalidInt;

            return .{ .constant = res };
        },
        .hyphen => {
            const inner_exp = try parse_factor(arena, tokens);
            return .{ .unop_neg = try utils.create(arena, inner_exp) };
        },
        .tilde => {
            const inner_exp = try parse_factor(arena, tokens);
            return .{ .unop_not = try utils.create(arena, inner_exp) };
        },
        .bang => {
            const inner_exp = try parse_factor(arena, tokens);
            return .{ .unop_lnot = try utils.create(arena, inner_exp) };
        },
        .l_paren => {
            const inner_exp = try parse_expr(arena, tokens, 0);
            try expect(.r_paren, tokens);

            return inner_exp;
        },
        else => return error.SyntaxError,
    }
}

fn parse_args(
    arena: std.mem.Allocator,
    tokens: *lexer.Tokenizer,
) Error!std.SegmentedList(ast.Expr, 0) {
    // assumes l_paren already consumed
    var ret: std.SegmentedList(ast.Expr, 0) = .{};

    const current = try tokens.next_force();

    args: switch (current.tag) {
        .r_paren => return ret,
        .comma => {
            const expr = try parse_expr(arena, tokens, 0);
            try ret.append(arena, expr);

            const n_token = try tokens.next_force();
            continue :args n_token.tag;
        },
        else => {
            tokens.put_back(current);
            continue :args .comma;
        },
    }
}

inline fn expect(
    comptime expected: lexer.Token.Tag,
    tokens: *lexer.Tokenizer,
) Error!ExpectResult(expected) {
    const actual = try tokens.next_force();
    if (actual.tag != expected)
        return error.SyntaxError;

    switch (expected) {
        .identifier => return tokens.buffer[actual.loc.start..actual.loc.end],
        else => {},
    }
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
        NotEnoughJunk,
        InvalidStorageClass,
        InvalidTypeSpecifier,
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
