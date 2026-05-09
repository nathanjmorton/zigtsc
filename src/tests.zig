const std = @import("std");
const testing = std.testing;
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGen = @import("codegen.zig").CodeGen;
const CodeGenJS = @import("codegen_js.zig").CodeGenJS;
const CodeGenCpp = @import("codegen_cpp.zig").CodeGenCpp;
const CodeGenCuda = @import("codegen_cuda.zig").CodeGenCuda;
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

// ── Class parsing tests ─────────────────────────────────────────────────

test "parse class decl" {
    const allocator = testing.allocator;
    const source =
        \\class Counter {
        \\    value: number;
        \\    constructor(init: number) {
        \\        this.value = init;
        \\    }
        \\    increment(): void {
        \\        this.value = this.value + 1;
        \\    }
        \\    getVal(): number {
        \\        return this.value;
        \\    }
        \\}
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    try testing.expect(root != null_node);
}

test "parse new expr" {
    const allocator = testing.allocator;
    const source =
        \\class Foo { x: number; }
        \\const f = new Foo();
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    _ = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
}

// ── Checker class tests ─────────────────────────────────────────────────

test "check class decl" {
    const allocator = testing.allocator;
    const source =
        \\class Point {
        \\    x: number;
        \\    y: number;
        \\    constructor(x: number, y: number) {
        \\        this.x = x;
        \\        this.y = y;
        \\    }
        \\    distFromOrigin(): number {
        \\        return this.x + this.y;
        \\    }
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

    // Should have registered one class
    try testing.expectEqual(@as(usize, 1), checker.classes.items.len);
    try testing.expectEqualStrings("Point", checker.classes.items[0].name);
    try testing.expectEqual(@as(usize, 2), checker.classes.items[0].fields.len);
    try testing.expectEqual(@as(usize, 1), checker.classes.items[0].methods.len);
    try testing.expectEqual(@as(usize, 2), checker.classes.items[0].constructor_params.len);
}

// ── JS codegen tests ────────────────────────────────────────────────────

test "e2e js hello world" {
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

    var codegen = CodeGenJS.init(&parser.tree, allocator);
    defer codegen.deinit();
    const js_out = try codegen.generate(root);

    try testing.expect(std.mem.indexOf(u8, js_out, "const message = \"hello world\";") != null);
    try testing.expect(std.mem.indexOf(u8, js_out, "console.log(message);") != null);
    // Should NOT contain type annotations
    try testing.expect(std.mem.indexOf(u8, js_out, ": string") == null);
}

test "e2e js function" {
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

    var codegen = CodeGenJS.init(&parser.tree, allocator);
    defer codegen.deinit();
    const js_out = try codegen.generate(root);

    try testing.expect(std.mem.indexOf(u8, js_out, "function add(a, b)") != null);
    try testing.expect(std.mem.indexOf(u8, js_out, "return (a + b);") != null);
    // No type annotations
    try testing.expect(std.mem.indexOf(u8, js_out, ": number") == null);
}

test "e2e js class" {
    const allocator = testing.allocator;
    const source =
        \\class Counter {
        \\    value: number;
        \\    constructor(init: number) {
        \\        this.value = init;
        \\    }
        \\    increment(): void {
        \\        this.value = this.value + 1;
        \\    }
        \\}
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();

    var codegen = CodeGenJS.init(&parser.tree, allocator);
    defer codegen.deinit();
    const js_out = try codegen.generate(root);

    try testing.expect(std.mem.indexOf(u8, js_out, "class Counter {") != null);
    try testing.expect(std.mem.indexOf(u8, js_out, "constructor(init)") != null);
    try testing.expect(std.mem.indexOf(u8, js_out, "this.value = init;") != null);
    try testing.expect(std.mem.indexOf(u8, js_out, "increment()") != null);
}

test "e2e js interface omitted" {
    const allocator = testing.allocator;
    const source =
        \\interface Point { x: number; y: number; }
        \\const p: number = 42;
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();

    var codegen = CodeGenJS.init(&parser.tree, allocator);
    defer codegen.deinit();
    const js_out = try codegen.generate(root);

    // Interface should be omitted
    try testing.expect(std.mem.indexOf(u8, js_out, "interface") == null);
    try testing.expect(std.mem.indexOf(u8, js_out, "Point") == null);
    try testing.expect(std.mem.indexOf(u8, js_out, "const p = 42;") != null);
}

// ── C++ codegen tests ───────────────────────────────────────────────────

test "e2e cpp class multi-file" {
    const allocator = testing.allocator;
    const source =
        \\class Counter {
        \\    value: i32;
        \\    constructor(init: i32) {
        \\        this.value = init;
        \\    }
        \\    getVal(): i32 {
        \\        return this.value;
        \\    }
        \\}
        \\const c = new Counter(10);
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);

    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    var codegen = CodeGenCpp.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const files = try codegen.generate(root);
    defer allocator.free(files);

    // Should produce 3 files: Counter.h, Counter.cpp, main.cpp
    try testing.expectEqual(@as(usize, 3), files.len);
    try testing.expectEqualStrings("Counter.h", files[0].name);
    try testing.expectEqualStrings("Counter.cpp", files[1].name);
    try testing.expectEqualStrings("main.cpp", files[2].name);

    // Header checks
    const header = files[0].content;
    try testing.expect(std.mem.indexOf(u8, header, "#pragma once") != null);
    try testing.expect(std.mem.indexOf(u8, header, "class Counter {") != null);
    try testing.expect(std.mem.indexOf(u8, header, "int32_t value;") != null);
    try testing.expect(std.mem.indexOf(u8, header, "Counter(int32_t init);") != null);
    try testing.expect(std.mem.indexOf(u8, header, "int32_t getVal();") != null);

    // Impl checks
    const impl = files[1].content;
    try testing.expect(std.mem.indexOf(u8, impl, "#include \"Counter.h\"") != null);
    try testing.expect(std.mem.indexOf(u8, impl, "Counter::Counter(") != null);
    try testing.expect(std.mem.indexOf(u8, impl, "Counter::getVal()") != null);
    try testing.expect(std.mem.indexOf(u8, impl, "this->value") != null);

    // Main checks
    const main_file = files[2].content;
    try testing.expect(std.mem.indexOf(u8, main_file, "#include \"Counter.h\"") != null);
    try testing.expect(std.mem.indexOf(u8, main_file, "int main()") != null);
    try testing.expect(std.mem.indexOf(u8, main_file, "new Counter(10)") != null);

    // Free allocated content
    for (files) |file| {
        allocator.free(file.name);
        allocator.free(file.content);
    }
}

test "e2e cpp free functions in main" {
    const allocator = testing.allocator;
    const source =
        \\function add(a: number, b: number): number {
        \\    return a + b;
        \\}
        \\console.log(add(1, 2));
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();

    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    var codegen = CodeGenCpp.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const files = try codegen.generate(root);
    defer allocator.free(files);

    // No classes → just main.cpp
    try testing.expectEqual(@as(usize, 1), files.len);
    try testing.expectEqualStrings("main.cpp", files[0].name);

    const main_file = files[0].content;
    try testing.expect(std.mem.indexOf(u8, main_file, "double add(double a, double b)") != null);
    try testing.expect(std.mem.indexOf(u8, main_file, "int main()") != null);
    try testing.expect(std.mem.indexOf(u8, main_file, "printf(") != null);

    for (files) |file| {
        allocator.free(file.name);
        allocator.free(file.content);
    }
}

// ── CUDA codegen tests ──────────────────────────────────────────────────

test "parse kernel decl" {
    const allocator = testing.allocator;
    const source =
        \\kernel function vecadd(a: f32[], b: f32[], c: f32[], n: i32): void {
        \\    const idx: i32 = threadIdx.x + blockIdx.x * blockDim.x;
        \\    if (idx < n) {
        \\        c[idx] = a[idx] + b[idx];
        \\    }
        \\}
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    try testing.expect(root != null_node);

    // First statement should be a kernel_decl
    const prog = parser.tree.nodes.items[root];
    try testing.expectEqual(prog.tag, .program);
    const first_idx = parser.tree.extra.items[prog.data.lhs];
    const first = parser.tree.nodes.items[first_idx];
    try testing.expectEqual(first.tag, .kernel_decl);
}

test "e2e cuda kernel" {
    const allocator = testing.allocator;
    const source =
        \\kernel function vecadd(a: f32[], b: f32[], c: f32[], n: i32): void {
        \\    const idx: i32 = threadIdx.x + blockIdx.x * blockDim.x;
        \\    if (idx < n) {
        \\        c[idx] = a[idx] + b[idx];
        \\    }
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

    var codegen = CodeGenCuda.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const cu_out = try codegen.generate(root);

    // Should contain CUDA headers and __global__ kernel
    try testing.expect(std.mem.indexOf(u8, cu_out, "#include <cuda_runtime.h>") != null);
    try testing.expect(std.mem.indexOf(u8, cu_out, "__global__ void vecadd(float* a, float* b, float* c, int32_t n)") != null);
    try testing.expect(std.mem.indexOf(u8, cu_out, "threadIdx.x") != null);
    try testing.expect(std.mem.indexOf(u8, cu_out, "blockIdx.x") != null);
    try testing.expect(std.mem.indexOf(u8, cu_out, "blockDim.x") != null);
    // Should NOT have a main() since there are no top-level statements
    try testing.expect(std.mem.indexOf(u8, cu_out, "int main(") == null);
}

// ── Import tests ────────────────────────────────────────────────────────

test "lex import and from keywords" {
    var lex = Lexer.init("import from");
    try testing.expectEqual(Token.Tag.kw_import, lex.next().tag);
    try testing.expectEqual(Token.Tag.kw_from, lex.next().tag);
    try testing.expectEqual(Token.Tag.eof, lex.next().tag);
}

test "parse import decl" {
    const allocator = testing.allocator;
    const source =
        \\import { Counter } from './counter';
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
    try testing.expect(root != null_node);

    // First statement should be an import_decl
    const prog = parser.tree.nodes.items[root];
    try testing.expectEqual(prog.tag, .program);
    const first_idx = parser.tree.extra.items[prog.data.lhs];
    const first = parser.tree.nodes.items[first_idx];
    try testing.expectEqual(first.tag, .import_decl);
}

test "parse import with multiple names" {
    const allocator = testing.allocator;
    const source =
        \\import { Foo, Bar } from './module';
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    _ = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);
}

test "e2e import skipped in codegen" {
    const allocator = testing.allocator;
    const source =
        \\import { Counter } from './counter';
        \\const x: number = 42;
        \\console.log(x);
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);

    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    // C codegen should skip import_decl and still produce main()
    var codegen = CodeGen.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const c_out = try codegen.generate(root);
    try testing.expect(std.mem.indexOf(u8, c_out, "int main(") != null);
    try testing.expect(std.mem.indexOf(u8, c_out, "printf(") != null);
    // Should NOT contain "import" in C output
    try testing.expect(std.mem.indexOf(u8, c_out, "import") == null);
}

// ── CUDA codegen tests (continued) ──────────────────────────────────────

test "e2e cuda kernel with host code" {
    const allocator = testing.allocator;
    const source =
        \\kernel function scale(arr: f32[], factor: f32, n: i32): void {
        \\    const i: i32 = threadIdx.x + blockIdx.x * blockDim.x;
        \\    if (i < n) {
        \\        arr[i] = arr[i] * factor;
        \\    }
        \\}
        \\const n: i32 = 1024;
        \\console.log(n);
    ;
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();
    try testing.expectEqual(@as(usize, 0), parser.errors.items.len);

    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    var codegen = CodeGenCuda.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const cu_out = try codegen.generate(root);

    // Kernel should be __global__
    try testing.expect(std.mem.indexOf(u8, cu_out, "__global__ void scale(") != null);
    // Should have main() for host code
    try testing.expect(std.mem.indexOf(u8, cu_out, "int main(void)") != null);
    try testing.expect(std.mem.indexOf(u8, cu_out, "printf(") != null);
}
