pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: usize,
        end: usize,
    };

    pub fn slice(self: Token, source: []const u8) []const u8 {
        return source[self.loc.start..self.loc.end];
    }

    pub const Tag = enum {
        // Literals
        number_literal,
        string_literal,
        true_literal,
        false_literal,

        // Identifiers
        identifier,

        // Keywords
        kw_let,
        kw_const,
        kw_function,
        kw_return,
        kw_if,
        kw_else,
        kw_while,
        kw_for,
        kw_interface,
        kw_type,
        kw_export,
        kw_class,
        kw_new,
        kw_this,
        kw_kernel,
        kw_import,
        kw_from,

        // Type keywords
        kw_number,
        kw_boolean,
        kw_string,
        kw_void,
        kw_i32,
        kw_i64,
        kw_f32,
        kw_f64,

        // Operators
        plus,
        minus,
        star,
        slash,
        percent,
        assign,
        equal,
        strict_equal,
        not_equal,
        strict_not_equal,
        less,
        greater,
        less_equal,
        greater_equal,
        ampersand_ampersand,
        pipe_pipe,
        bang,
        plus_assign,
        minus_assign,
        star_assign,
        slash_assign,

        // Punctuation
        colon,
        semicolon,
        comma,
        dot,
        lparen,
        rparen,
        lbrace,
        rbrace,
        lbracket,
        rbracket,
        arrow, // =>
        question_mark,

        // Special
        eof,
        invalid,

        pub fn isKeyword(tag: Tag) bool {
            return switch (tag) {
                .kw_let,
                .kw_const,
                .kw_function,
                .kw_return,
                .kw_if,
                .kw_else,
                .kw_while,
                .kw_for,
                .kw_interface,
                .kw_type,
                .kw_export,
                .kw_class,
                .kw_new,
                .kw_this,
                .kw_kernel,
                .kw_import,
                .kw_from,
                .kw_number,
                .kw_boolean,
                .kw_string,
                .kw_void,
                .kw_i32,
                .kw_i64,
                .kw_f32,
                .kw_f64,
                .true_literal,
                .false_literal,
                => true,
                else => false,
            };
        }
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "let", .kw_let },
        .{ "const", .kw_const },
        .{ "function", .kw_function },
        .{ "return", .kw_return },
        .{ "if", .kw_if },
        .{ "else", .kw_else },
        .{ "while", .kw_while },
        .{ "for", .kw_for },
        .{ "interface", .kw_interface },
        .{ "type", .kw_type },
        .{ "export", .kw_export },
        .{ "class", .kw_class },
        .{ "new", .kw_new },
        .{ "this", .kw_this },
        .{ "kernel", .kw_kernel },
        .{ "import", .kw_import },
        .{ "from", .kw_from },
        .{ "number", .kw_number },
        .{ "boolean", .kw_boolean },
        .{ "string", .kw_string },
        .{ "void", .kw_void },
        .{ "i32", .kw_i32 },
        .{ "i64", .kw_i64 },
        .{ "f32", .kw_f32 },
        .{ "f64", .kw_f64 },
        .{ "true", .true_literal },
        .{ "false", .false_literal },
    });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }
};

const std = @import("std");
