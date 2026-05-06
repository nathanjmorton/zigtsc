const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGen = @import("codegen.zig").CodeGen;
const CodeGenJS = @import("codegen_js.zig").CodeGenJS;
const CodeGenCpp = @import("codegen_cpp.zig").CodeGenCpp;

const Target = enum { c, cpp, js };

const HELP_TEXT =
    \\zigtsc — TypeScript subset → C / C++ / JS compiler
    \\
    \\Usage:
    \\  zigtsc <input.ts> [output] [-target c|cpp|js]
    \\  zigtsc init [directory]
    \\  zigtsc help
    \\
    \\Commands:
    \\  init [dir]    Scaffold a new project with a starter main.ts
    \\  upgrade       Update zigtsc to the latest release
    \\  help          Print this help message
    \\
    \\Targets:
    \\  c   (default) Single-file C output. Compile with zigc.
    \\  js            JavaScript output. Run with node.
    \\  cpp           Multi-file C++ output (.h/.cpp per class). Compile with zigc.
    \\
    \\Examples:
    \\  zigtsc init myapp                          # scaffold a project
    \\  zigtsc myapp/main.ts output.c              # transpile to C
    \\  zigtsc myapp/main.ts -target js output.js  # transpile to JS
    \\  zigtsc myapp/main.ts -target cpp out/      # transpile to C++ (multi-file)
    \\
    \\Compile C/C++ output with zigc:
    \\  zigc init fib-app && cp output.c fib-app/src/main.c
    \\  cd fib-app && zigc run
    \\
    \\Install zigc: https://zigc.nathanjmorton.com
    \\Docs:         https://zigtsc.nathanjmorton.com/docs
    \\GitHub:       https://github.com/nathanjmorton/zigtsc
    \\
;

const INIT_TEMPLATE =
    \\// ── zigtsc starter project ──────────────────────────────────────────────
    \\//
    \\// Transpile to any of three targets:
    \\//
    \\//   zigtsc main.ts                         # C output to stdout
    \\//   zigtsc main.ts output.c                # C output to file
    \\//   zigtsc main.ts -target js output.js    # JavaScript output
    \\//   zigtsc main.ts -target cpp out/        # C++ multi-file output
    \\//
    \\// Compile C/C++ output with zigc (https://zigc.nathanjmorton.com):
    \\//   zigc init myapp && cp output.c myapp/src/main.c && cd myapp && zigc run
    \\
    \\// ── Interfaces ──────────────────────────────────────────────────────────
    \\// Interfaces compile to C structs, are omitted in JS output,
    \\// and become C++ structs in the cpp target.
    \\
    \\interface Point {
    \\    x: number;
    \\    y: number;
    \\}
    \\
    \\// ── Functions ───────────────────────────────────────────────────────────
    \\
    \\function distance(a: Point, b: Point): number {
    \\    let dx: number = b.x - a.x;
    \\    let dy: number = b.y - a.y;
    \\    return dx * dx + dy * dy;
    \\}
    \\
    \\// ── Classes ─────────────────────────────────────────────────────────────
    \\// Go-style classes: no inheritance, no static methods.
    \\// In C++ target, each class gets its own .h/.cpp pair.
    \\// In JS target, classes emit directly as ES6 classes.
    \\
    \\class Counter {
    \\    value: i32;
    \\
    \\    constructor(init: i32) {
    \\        this.value = init;
    \\    }
    \\
    \\    increment(): void {
    \\        this.value = this.value + 1;
    \\    }
    \\
    \\    decrement(): void {
    \\        this.value = this.value - 1;
    \\    }
    \\
    \\    getVal(): i32 {
    \\        return this.value;
    \\    }
    \\}
    \\
    \\// ── Top-level code ──────────────────────────────────────────────────────
    \\
    \\const p1: Point = { x: 0, y: 0 };
    \\const p2: Point = { x: 3, y: 4 };
    \\console.log(distance(p1, p2));
    \\
    \\const c = new Counter(10);
    \\c.increment();
    \\c.increment();
    \\c.decrement();
    \\console.log(c.getVal());
    \\
;

fn runUpgrade() void {
    std.debug.print(
        \\zigtsc upgrade
        \\
        \\If installed via Homebrew:
        \\  brew upgrade zigtsc
        \\
        \\If installed via shell script:
        \\  curl -fsSL https://raw.githubusercontent.com/nathanjmorton/zigtsc/main/install.sh | bash
        \\
    , .{});
}

fn runInit(io: std.Io, dir: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    if (!std.mem.eql(u8, dir, ".")) {
        cwd.createDirPath(io, dir) catch {};
    }
    const sub_path = if (std.mem.eql(u8, dir, "."))
        "main.ts"
    else blk: {
        // We need to build "dir/main.ts" but we only have comptime concat or fmt.
        // Use a fixed buffer.
        var buf: [512]u8 = undefined;
        const len = (std.fmt.bufPrint(&buf, "{s}/main.ts", .{dir}) catch return error.PathTooLong).len;
        break :blk buf[0..len];
    };
    cwd.writeFile(io, .{ .sub_path = sub_path, .data = INIT_TEMPLATE }) catch {
        std.debug.print("error: cannot write '{s}'\n", .{sub_path});
        return error.WriteError;
    };
    std.debug.print("created {s}\n\n", .{sub_path});
    std.debug.print("next steps:\n", .{});
    std.debug.print("  zigtsc {s} -target js output.js    # transpile to JS\n", .{sub_path});
    std.debug.print("  zigtsc {s} -target cpp out/        # transpile to C++\n", .{sub_path});
    std.debug.print("  zigtsc {s} output.c                # transpile to C\n", .{sub_path});
}

pub fn main(init_arg: std.process.Init) !void {
    const allocator = init_arg.gpa;
    const io = init_arg.io;

    // Collect args (skip argv[0])
    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);
    var it = std.process.Args.Iterator.init(init_arg.minimal.args);
    _ = it.skip();
    while (it.next()) |arg| try args_list.append(allocator, arg);
    const args = args_list.items;

    if (args.len < 1) {
        std.debug.print("{s}", .{HELP_TEXT});
        return;
    }

    // Check for subcommands and flags first
    if (std.mem.eql(u8, args[0], "help") or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        std.debug.print("{s}", .{HELP_TEXT});
        return;
    }

    if (std.mem.eql(u8, args[0], "init")) {
        const dir = if (args.len > 1) args[1] else ".";
        return runInit(io, dir);
    }

    if (std.mem.eql(u8, args[0], "upgrade")) {
        runUpgrade();
        return;
    }

    // Parse flags
    var target: Target = .c;
    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-target") and i + 1 < args.len) {
            i += 1;
            if (std.mem.eql(u8, args[i], "cpp")) target = .cpp
            else if (std.mem.eql(u8, args[i], "js")) target = .js
            else target = .c;
        } else if (input_path == null) {
            input_path = args[i];
        } else {
            output_path = args[i];
        }
    }

    const in_path = input_path orelse {
        std.debug.print("{s}", .{HELP_TEXT});
        return error.MissingArgument;
    };

    const cwd = std.Io.Dir.cwd();
    const source = cwd.readFileAlloc(io, in_path, allocator, .unlimited) catch {
        std.debug.print("error: cannot read '{s}'\n", .{in_path});
        return error.FileNotFound;
    };
    defer allocator.free(source);

    // Parse
    var parser = Parser.init(source, allocator);
    defer parser.deinit();
    const root = try parser.parse();
    defer parser.tree.deinit();

    if (parser.errors.items.len > 0) {
        for (parser.errors.items) |err| {
            const loc_str = source[err.loc.start..@min(err.loc.end, source.len)];
            std.debug.print("error: {s} at '{s}'\n", .{ err.msg, loc_str });
        }
        return error.ParseError;
    }

    // Type check
    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);

    switch (target) {
        .c => {
            var codegen = CodeGen.init(&parser.tree, &checker, allocator);
            defer codegen.deinit();
            const c_source = try codegen.generate(root);
            if (output_path) |op| {
                cwd.writeFile(io, .{ .sub_path = op, .data = c_source }) catch {
                    std.debug.print("error: cannot write '{s}'\n", .{op});
                    return error.WriteError;
                };
                std.debug.print("wrote {s} ({d} bytes)\n", .{ op, c_source.len });
            } else {
                std.debug.print("{s}", .{c_source});
            }
        },
        .js => {
            var codegen = CodeGenJS.init(&parser.tree, allocator);
            defer codegen.deinit();
            const js_source = try codegen.generate(root);
            if (output_path) |op| {
                cwd.writeFile(io, .{ .sub_path = op, .data = js_source }) catch {
                    std.debug.print("error: cannot write '{s}'\n", .{op});
                    return error.WriteError;
                };
                std.debug.print("wrote {s} ({d} bytes)\n", .{ op, js_source.len });
            } else {
                std.debug.print("{s}", .{js_source});
            }
        },
        .cpp => {
            var codegen = CodeGenCpp.init(&parser.tree, &checker, allocator);
            defer codegen.deinit();
            const files = try codegen.generate(root);
            if (output_path) |out_dir| {
                // Write each file to the output directory
                for (files) |file| {
                    const sub = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ out_dir, file.name });
                    defer allocator.free(sub);
                    cwd.writeFile(io, .{ .sub_path = sub, .data = file.content }) catch {
                        std.debug.print("error: cannot write '{s}'\n", .{sub});
                        return error.WriteError;
                    };
                    std.debug.print("wrote {s} ({d} bytes)\n", .{ sub, file.content.len });
                }
            } else {
                // Print all files to stdout with markers
                for (files) |file| {
                    std.debug.print("// === {s} ===\n{s}\n", .{ file.name, file.content });
                }
            }
        },
    }
}
