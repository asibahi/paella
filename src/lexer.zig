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
        l_paren, // (
        r_paren, // )
        l_brace, // {
        r_brace, // }
        semicolon, // ;

        tilde, // ~
        hyphen, // -
        plus, // +
        asterisk, // *
        f_slash, // /
        percent, // %

        bang, // !
        double_ambersand, // &&
        double_pipe, // ||
        double_equals, // ==
        bang_equal, // !=
        lesser_than, // <
        greater_than, // >,
        lesser_equals, // <=
        greater_equals, // >=

        type_int,

        keyword_void,
        keyword_return,

        number_literal,

        identifier, // useful for state for now
        invalid,

        pub fn binop_precedence(self: @This()) ?u8 {
            return switch (self) {
                .asterisk, // *
                .f_slash, // /
                .percent, // %
                => 50,
                .hyphen, // -
                .plus, // +
                => 45,
                else => null,
            };
        }
    };
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: usize = 0,

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{ .buffer = buffer };
    }

    const State = enum {
        start,
        identifier,
        int,
        hyphen,

        bang,
        ambersand,
        pipe,
        equals,
        lesser_than,
        greater_than,
    };

    pub inline fn put_back(self: *Tokenizer, token: Token) void {
        self.index = token.loc.start;
    }

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
                0 => if (self.index == self.buffer.len) {
                    return null;
                } else {
                    result.tag = .invalid;
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
                '0'...'9' => {
                    result.tag = .number_literal;
                    self.index += 1;
                    continue :state .int;
                },

                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                },
                ')' => {
                    result.tag = .r_paren;
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
                ';' => {
                    result.tag = .semicolon;
                    self.index += 1;
                },

                '-' => continue :state .hyphen,
                '~' => {
                    result.tag = .tilde;
                    self.index += 1;
                },
                '+' => {
                    result.tag = .plus;
                    self.index += 1;
                },
                '*' => {
                    result.tag = .asterisk;
                    self.index += 1;
                },
                '/' => {
                    result.tag = .f_slash;
                    self.index += 1;
                },
                '%' => {
                    result.tag = .percent;
                    self.index += 1;
                },
                '!' => continue :state .bang,
                '&' => continue :state .ambersand,
                '|' => continue :state .pipe,
                '=' => continue :state .equals,
                '<' => continue :state .lesser_than,
                '>' => continue :state .greater_than,
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

            .hyphen => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-' => result.tag = .invalid,
                    else => result.tag = .hyphen,
                }
            },

            .bang => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        self.index += 1;
                        result.tag = .bang_equal;
                    },
                    else => result.tag = .bang,
                }
            },
            .ambersand => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '&' => {
                        self.index += 1;
                        result.tag = .double_ambersand;
                    },
                    else => result.tag = .invalid,
                }
            },
            .pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '|' => {
                        self.index += 1;
                        result.tag = .double_pipe;
                    },
                    else => result.tag = .invalid,
                }
            },
            .equals => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        self.index += 1;
                        result.tag = .double_equals;
                    },
                    else => result.tag = .invalid, // todo
                }
            },
            .lesser_than => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        self.index += 1;
                        result.tag = .lesser_equals;
                    },
                    else => result.tag = .lesser_than,
                }
            },
            .greater_than => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        self.index += 1;
                        result.tag = .greater_equals;
                    },
                    else => result.tag = .greater_than,
                }
            },
        }

        result.loc.end = self.index;
        return result;
    }
};
