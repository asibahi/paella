const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "return", .keyword_return },
        .{ "int", .type_int },
        .{ "void", .keyword_void },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }

    pub const Tag = enum {
        l_paren,
        r_paren,
        l_brace,
        r_brace,
        semicolon,
        number_literal,
        type_int,
        keyword_void,
        keyword_return,

        identifier, // useful for state for now
        invalid,

        pub fn lexeme(tag: Tag) ?[]const u8 {
            return switch (tag) {
                .invalid,
                .number_literal,
                .identifier,
                => null,

                .l_paren => "(",
                .r_paren => ")",
                .l_brace => "{",
                .r_brace => "}",

                .semicolon => ";",

                .type_int => "int",
                .keyword_void => "void",
                .keyword_return => "return",
            };
        }

        pub fn symbol(tag: Tag) []const u8 {
            return tag.lexeme() orelse switch (tag) {
                .invalid => "invalid token",
                .identifier => "an identifier",
                .number_literal => "a number literal",
                else => unreachable,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize = 0,

    /// For debugging purposes.
    pub fn dump(self: *Tokenizer, token: *const Token) void {
        std.debug.print("{s} \"{s}\"\n", .{ @tagName(token.tag), self.buffer[token.loc.start..token.loc.end] });
    }

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{ .buffer = buffer };
    }

    const State = enum {
        start,
        identifier,
        int,
    };

    pub fn next(self: *Tokenizer) ?Token {
        var result: Token = .{
            .tag = undefined,
            .loc = .{
                .start = self.index,
                .end = undefined,
            },
        };
        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                0 => {
                    if (self.index == self.buffer.len) {
                        return null;
                    } else {
                        result.tag = .invalid;
                    }
                },
                ' ', '\n', '\t', '\r' => {
                    self.index += 1;
                    result.loc.start = self.index;
                    continue :state .start;
                },
                'a'...'z', 'A'...'Z', '_' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                },
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                },
                '0'...'9' => {
                    result.tag = .number_literal;
                    self.index += 1;
                    continue :state .int;
                },
                else => result.tag = .invalid,
            },

            .identifier => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                    else => {
                        const ident = self.buffer[result.loc.start..self.index];
                        if (Token.getKeyword(ident)) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },

            .int => switch (self.buffer[self.index]) {
                '0'...'9' => {
                    self.index += 1;
                    continue :state .int;
                },
                'a'...'z', 'A'...'Z' => result.tag = .invalid,
                else => {},
            },
        }

        result.loc.end = self.index;
        return result;
    }
};
