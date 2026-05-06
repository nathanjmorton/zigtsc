const std = @import("std");
const Token = @import("token.zig").Token;

pub const Lexer = struct {
    source: []const u8,
    pos: usize = 0,

    pub fn init(source: []const u8) Lexer {
        return .{ .source = source };
    }

    pub fn next(self: *Lexer) Token {
        self.skipWhitespaceAndComments();
        if (self.pos >= self.source.len)
            return .{ .tag = .eof, .loc = .{ .start = self.pos, .end = self.pos } };
        const start = self.pos;
        const c = self.source[self.pos];
        if (c == '"' or c == '\'') return self.readString(c, start);
        if (std.ascii.isDigit(c) or (c == '.' and self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])))
            return self.readNumber(start);
        if (std.ascii.isAlphabetic(c) or c == '_' or c == '$') return self.readIdentifier(start);
        return self.readOperator(start);
    }

    fn readString(self: *Lexer, quote: u8, start: usize) Token {
        self.pos += 1;
        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\') self.pos += 1;
            self.pos += 1;
        }
        if (self.pos < self.source.len) self.pos += 1;
        return .{ .tag = .string_literal, .loc = .{ .start = start, .end = self.pos } };
    }

    fn readNumber(self: *Lexer, start: usize) Token {
        while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '.'))
            self.pos += 1;
        if (self.pos < self.source.len and (self.source[self.pos] == 'e' or self.source[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-'))
                self.pos += 1;
            while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) self.pos += 1;
        }
        return .{ .tag = .number_literal, .loc = .{ .start = start, .end = self.pos } };
    }

    fn readIdentifier(self: *Lexer, start: usize) Token {
        while (self.pos < self.source.len and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_' or self.source[self.pos] == '$'))
            self.pos += 1;
        const text = self.source[start..self.pos];
        const tag = Token.getKeyword(text) orelse .identifier;
        return .{ .tag = tag, .loc = .{ .start = start, .end = self.pos } };
    }

    fn readOperator(self: *Lexer, start: usize) Token {
        const c = self.source[self.pos];
        self.pos += 1;
        const tag: Token.Tag = switch (c) {
            '(' => .lparen, ')' => .rparen, '{' => .lbrace, '}' => .rbrace,
            '[' => .lbracket, ']' => .rbracket, ':' => .colon, ';' => .semicolon,
            ',' => .comma, '.' => .dot, '?' => .question_mark, '%' => .percent,
            '+' => if (self.match('=')) .plus_assign else .plus,
            '-' => if (self.match('=')) .minus_assign else .minus,
            '*' => if (self.match('=')) .star_assign else .star,
            '/' => if (self.match('=')) .slash_assign else .slash,
            '=' => blk: {
                if (self.match('=')) { break :blk if (self.match('=')) .strict_equal else .equal; }
                break :blk if (self.match('>')) .arrow else .assign;
            },
            '!' => blk: {
                if (self.match('=')) { break :blk if (self.match('=')) .strict_not_equal else .not_equal; }
                break :blk .bang;
            },
            '<' => if (self.match('=')) .less_equal else .less,
            '>' => if (self.match('=')) .greater_equal else .greater,
            '&' => if (self.match('&')) .ampersand_ampersand else .invalid,
            '|' => if (self.match('|')) .pipe_pipe else .invalid,
            else => .invalid,
        };
        return .{ .tag = tag, .loc = .{ .start = start, .end = self.pos } };
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.pos < self.source.len and self.source[self.pos] == expected) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn skipWhitespaceAndComments(self: *Lexer) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') { self.pos += 1; continue; }
            if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') self.pos += 1;
                continue;
            }
            if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
                self.pos += 2;
                while (self.pos + 1 < self.source.len) {
                    if (self.source[self.pos] == '*' and self.source[self.pos + 1] == '/') { self.pos += 2; break; }
                    self.pos += 1;
                }
                continue;
            }
            break;
        }
    }
};
