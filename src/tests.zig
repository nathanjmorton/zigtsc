const std = @import("std");
const testing = std.testing;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGen = @import("codegen.zig").CodeGen;
const ast_mod = @import("ast.zig");
const null_node = ast_mod.null_node;

// ── Lexer tests ─────────────────────────────────────────────────────────

test "lex keywords" {
    var lex = Lexer.init("let const function return if else while for interface");
    try testing.expectEqual(Token.Tag.kw_let, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_const, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_function, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_return, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_if, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_else, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_while, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_for, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_interface, lex.next().tag);
    try testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

test "lex operators" {
    var lex = Lexer.init("+ - * / = == === != !== < > <= >= && ||");
    try testing.expectEqual(Token.Tag.plus, lex.next().tag);
    try testing.expectEqual(Token.Tag.minus, lex.next().tag);
    try testing.expectEqual(Token.Tag.star, lex.next().tag);
    try testing.expectEqual(Token.Tag.slash, lex.next().tag);
    try testing.expectEqual(Token.Tag.assign, lex.next().tag);
    try testing.expectEqual(Token.Tag.equal, lex.next().tag);
    try testing.expectEqual(Token.Tag.strict_equal, lex.next().tag);
    try testing.expectEqual(Token.Tag.not_equal, lex.next().tag);
    try testing.expectEqual(Token.Tag.strict_not_equal, lex.next().tag);
    try testing.expectEqual(Token.Tag.less, lex.next().tag);
    try testing.expectEqual(Token.Tag.greater, lex.next().tag);
    try testing.expectEqual(Token.Tag.less_equal, lex.next().tag);
    try testing.expectEqual(Token.Tag.greater_equal, lex.next().tag);
    try testing.expectEqual(Token.Tag.ampersand_ampersand, lex.next().tag);
    try testing.expectEqual(Token.Tag.pipe_pipe, lex.next().tag);
}

test "lex number literal" {
    const source = "42 3.14 1e10";
    var lex = Lexer.init(source);
    const t1 = lex.next();
    try testing.expectEqual(Token.Tag.number_literal, t1.tag);
    try testing.expectEqualStrings("42", t1.slice(source));

    const t2 = lex.next();
    try testing.expectEqual(Token.Tag.number_literal, t2.tag);
    try testing.expectEqualStrings("3.14", t2.slice(source));

    const t3 = lex.next();
    try testing.expectEqual(Token.Tag.number_literal, t3.tag);
    try testing.expectEqualStrings("1e10", t3.slice(source));
}

test "lex string literal" {
    const source =
        \\"hello" 'world'
    ;
    var lex = Lexer.init(source);
    const t1 = lex.next();
    try testing.expectEqual(Token.Tag.string_literal, t1.tag);
    try testing.expectEqualStrings("\"hello\"", t1.slice(source));
    const t2 = lex.next();
    try testing.expectEqual(Token.Tag.string_literal, t2.tag);
    try testing.expectEqualStrings("'world'", t2.slice(source));
}

test "lex skips comments" {
    var lex = Lexer.init("a // comment\nb /* block */ c");
    try testing.expectEqual(Token.Tag.identifier, lex.next().tag);
    try testing.expectEqual(Token.Tag.identifier, lex.next().tag);
    try testing.expectEqual(Token.Tag.identifier, lex.next().tag);
    try testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

// ── Parser tests ────────────────────────────────────────────────────────

test "parse var decl" {
    const allocator = testing.allocator;
    var parser = Parser.init("let x: number = 42;", allocator);
    defer parser.deinit();
    const root = try parser.parse();
    try testing.expect(root != null_node);
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    parser.tree.deinit();
}

test "parse function decl" {
    const allocator = testing.allocator;
    var parser = Parser.init("function add(a: number, b: number): number { return a + b; }", allocator);
    defer parser.deinit();
    const root = try parser.parse();
    try testing.expect(root != null_node);
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    parser.tree.deinit();
}

test "parse interface decl" {
    const allocator = testing.allocator;
    var parser = Parser.init("interface Point { x: number; y: number; }", allocator);
    defer parser.deinit();
    const root = try parser.parse();
    try testing.expect(root != null_node);
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    parser.tree.deinit();
}

test "parse if stmt" {
    const allocator = testing.allocator;
    var parser = Parser.init("if (x > 0) { return x; } else { return 0; }", allocator);
    defer parser.deinit();
    const root = try parser.parse();
    try testing.expect(root != null_node);
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    parser.tree.deinit();
}

test "parse for stmt" {
    const allocator = testing.allocator;
    var parser = Parser.init("for (let i: number = 0; i < 10; i += 1) { console.log(i); }", allocator);
    defer parser.deinit();
    const root = try parser.parse();
    try testing.expect(root != null_node);
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    parser.tree.deinit();
}

// ── End-to-end codegen tests ────────────────────────────────────────────

test "e2e hello world" {
    const allocator = testing.allocator;
    const source =
        \\const message: string = "hello world";
        \\console.log(message);
    ;

    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);

    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    var codegen = CodeGen.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const c_out = try codegen.generate(root);

    // Should contain printf and #include
    try testing.expect(std.mem.indexOf(u8, c_out, "#include <stdio.h>") != null);
    try testing.expect(std.mem.indexOf(u8, c_out, "printf(") != null);
    try testing.expect(std.mem.indexOf(u8, c_out, "int main(") != null);
}

test "e2e function" {
    const allocator = testing.allocator;
    const source =
        \\function add(a: number, b: number): number {
        \\    return a + b;
        \\}
    ;

    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);

    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    var codegen = CodeGen.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const c_out = try codegen.generate(root);

    try testing.expect(std.mem.indexOf(u8, c_out, "double add(double a, double b)") != null);
    try testing.expect(std.mem.indexOf(u8, c_out, "return (a + b)") != null);
}

test "e2e interface to struct" {
    const allocator = testing.allocator;
    const source =
        \\interface Point {
        \\    x: number;
        \\    y: number;
        \\}
    ;

    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);

    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    var codegen = CodeGen.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const c_out = try codegen.generate(root);

    try testing.expect(std.mem.indexOf(u8, c_out, "typedef struct {") != null);
    try testing.expect(std.mem.indexOf(u8, c_out, "double x;") != null);
    try testing.expect(std.mem.indexOf(u8, c_out, "double y;") != null);
    try testing.expect(std.mem.indexOf(u8, c_out, "} Point;") != null);
}
