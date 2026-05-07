const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGen = @import("codegen.zig").CodeGen;
const CodeGenJS = @import("codegen_js.zig").CodeGenJS;
const CodeGenCpp = @import("codegen_cpp.zig").CodeGenCpp;
const NodeIndex = @import("ast.zig").NodeIndex;

// ── Version ───────────────────────────────────────────────────────────────────

const VERSION = "0.2.0";

const Target = enum { c, cpp, js, all };

const HELP_TEXT =
    \\zigtsc — TypeScript subset → C / C++ / JS compiler
    \\
    \\Usage:
    \\  zigtsc                                     # transpile main.ts → .h .c .cpp .js
    \\  zigtsc <input.ts>                          # transpile to all targets
    \\  zigtsc <input.ts> -target c|cpp|js [out]   # single target
    \\  zigtsc init [directory]                     # scaffold a project
    \\  zigtsc upgrade                              # upgrade to latest release
    \\
    \\With no -target flag, zigtsc emits all four files named after the input:
    \\  <base>.h    unified header (#ifdef __cplusplus)
    \\  <base>.c    C entrypoint with bridge calls
    \\  <base>.cpp  C++ class implementations + extern "C" bridge
    \\  <base>.js   JavaScript output
    \\
    \\Compile the C/C++ output with zigc:
    \\  zigc init myapp --ts && cd myapp && zigtsc main.ts && zigc run
    \\
    \\Docs:   https://zigtsc.nathanjmorton.com/docs
    \\GitHub: https://github.com/nathanjmorton/zigtsc
    \\
;

const INIT_TEMPLATE =
    \\// zigtsc starter — transpile with: zigtsc main.ts
    \\//
    \\// Produces: main.h  main.c  main.cpp  main.js
    \\// Compile:  zigc init myapp --ts && cd myapp && zigtsc main.ts && zigc run
    \\
    \\interface Point {
    \\    x: number;
    \\    y: number;
    \\}
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
    \\    getVal(): i32 {
    \\        return this.value;
    \\    }
    \\}
    \\
    \\const p: Point = { x: 3, y: 4 };
    \\console.log(p.x);
    \\
    \\const c = new Counter(0);
    \\c.increment();
    \\c.increment();
    \\c.increment();
    \\console.log(c.getVal());
    \\
;

// ── Upgrade ──────────────────────────────────────────────────────────────────

fn cmdUpgrade(io: std.Io, allocator: std.mem.Allocator) !void {
    const GITHUB_API = "https://api.github.com/repos/nathanjmorton/zigtsc/releases/latest";

    // 1. Fetch latest release tag from GitHub API.
    const api_result = try std.process.run(allocator, io, .{
        .argv = &.{ "curl", "-sfL", "-H", "Accept: application/vnd.github.v3+json", GITHUB_API },
    });
    defer allocator.free(api_result.stdout);
    defer allocator.free(api_result.stderr);

    const api_ok = switch (api_result.term) { .exited => |c| c == 0, else => false };
    if (!api_ok or api_result.stdout.len == 0) {
        std.debug.print("error: failed to check for updates\n", .{});
        return error.FetchFailed;
    }

    // Extract "tag_name" from the JSON response.
    const tag = extractJsonString(api_result.stdout, "tag_name") orelse {
        std.debug.print("error: could not parse latest release\n", .{});
        return error.ParseFailed;
    };

    // Strip leading 'v' if present for version comparison.
    const latest_version = if (tag.len > 0 and tag[0] == 'v') tag[1..] else tag;

    if (std.mem.eql(u8, latest_version, VERSION)) {
        std.debug.print("zigtsc is already up to date (v{s})\n", .{VERSION});
        return;
    }

    std.debug.print("Upgrading zigtsc v{s} → {s}\n", .{ VERSION, tag });

    // 2. Detect current platform.
    const platform = comptime detectTarget();

    // 3. Build download URL.
    const download_url = try std.fmt.allocPrint(allocator,
        "https://github.com/nathanjmorton/zigtsc/releases/download/{s}/zigtsc-{s}.tar.gz",
        .{ tag, platform });
    defer allocator.free(download_url);

    // 4. Find the actual binary location via `which zigtsc`.
    const which_result = try std.process.run(allocator, io, .{
        .argv = &.{ "which", "zigtsc" },
    });
    defer allocator.free(which_result.stdout);
    defer allocator.free(which_result.stderr);

    const which_ok = switch (which_result.term) { .exited => |c| c == 0, else => false };
    if (!which_ok or which_result.stdout.len == 0) {
        std.debug.print("error: could not find zigtsc on PATH\n", .{});
        return error.NotFound;
    }
    const self_path = std.mem.trimEnd(u8, which_result.stdout, "\n\r ");

    // Detect Homebrew installs and warn the user.
    if (std.mem.indexOf(u8, self_path, "/homebrew/") != null or
        std.mem.indexOf(u8, self_path, "/Cellar/") != null)
    {
        std.debug.print("zigtsc is installed via Homebrew ({s}).\n", .{self_path});
        std.debug.print("Use 'brew upgrade zigtsc' instead of 'zigtsc upgrade'.\n", .{});
        return;
    }

    // 5. Download to a temp file and extract.
    const tmp_tar = try std.fmt.allocPrint(allocator, "{s}.tar.gz", .{self_path});
    defer allocator.free(tmp_tar);

    const dl_result = try std.process.run(allocator, io, .{
        .argv = &.{ "curl", "-fL", "--progress-bar", "-o", tmp_tar, download_url },
    });
    defer allocator.free(dl_result.stdout);
    defer allocator.free(dl_result.stderr);

    const dl_ok = switch (dl_result.term) { .exited => |c| c == 0, else => false };
    if (!dl_ok) {
        std.debug.print("error: failed to download {s}\n", .{download_url});
        return error.DownloadFailed;
    }

    // Extract the binary, overwriting the existing one.
    const bin_dir = self_path[0 .. std.mem.lastIndexOfScalar(u8, self_path, '/') orelse 0];
    const extract_result = try std.process.run(allocator, io, .{
        .argv = &.{ "tar", "-xzf", tmp_tar, "-C", bin_dir },
    });
    defer allocator.free(extract_result.stdout);
    defer allocator.free(extract_result.stderr);

    const extract_ok = switch (extract_result.term) { .exited => |c| c == 0, else => false };
    if (!extract_ok) {
        std.debug.print("error: failed to extract update\n", .{});
        return error.ExtractFailed;
    }

    // Clean up the tarball.
    const cwd = std.Io.Dir.cwd();
    cwd.deleteFile(io, tmp_tar) catch {};

    // Make executable.
    const chmod_result = try std.process.run(allocator, io, .{
        .argv = &.{ "chmod", "+x", self_path },
    });
    defer allocator.free(chmod_result.stdout);
    defer allocator.free(chmod_result.stderr);

    std.debug.print("zigtsc upgraded to {s}\n", .{tag});
}

/// Extract the string value for a given key inside a JSON object fragment.
fn extractJsonString(block: []const u8, key: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (pos < block.len) {
        const q1 = std.mem.indexOfScalarPos(u8, block, pos, '"') orelse return null;
        const ks = q1 + 1;
        const q2 = std.mem.indexOfScalarPos(u8, block, ks, '"') orelse return null;
        const found_key = block[ks..q2];
        pos = q2 + 1;
        if (std.mem.eql(u8, found_key, key)) {
            // Next quoted string is the value.
            const v1 = std.mem.indexOfScalarPos(u8, block, pos, '"') orelse return null;
            const vs = v1 + 1;
            const v2 = std.mem.indexOfScalarPos(u8, block, vs, '"') orelse return null;
            return block[vs..v2];
        }
    }
    return null;
}

/// Detect the Zig target triple for the current platform at comptime.
fn detectTarget() []const u8 {
    const arch = @import("builtin").cpu.arch;
    const os = @import("builtin").os.tag;
    if (os == .macos) {
        if (arch == .aarch64) return "aarch64-macos";
        if (arch == .x86_64) return "x86_64-macos";
    }
    if (os == .linux) {
        if (arch == .aarch64) return "aarch64-linux-gnu";
        if (arch == .x86_64) return "x86_64-linux-gnu";
    }
    @compileError("unsupported platform for zigtsc upgrade");
}

fn runInit(io: std.Io, dir: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    if (!std.mem.eql(u8, dir, ".")) {
        cwd.createDirPath(io, dir) catch {};
    }
    const sub_path = if (std.mem.eql(u8, dir, "."))
        "main.ts"
    else blk: {
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
    std.debug.print("  zigtsc {s}                         # transpile to .h .c .cpp .js\n", .{sub_path});
    std.debug.print("  zigc init myapp --ts               # scaffold zigc project with main.ts\n", .{});
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
        // No args: look for main.ts in cwd
        const cwd = std.Io.Dir.cwd();
        const source = cwd.readFileAlloc(io, "main.ts", allocator, .unlimited) catch {
            std.debug.print("{s}", .{HELP_TEXT});
            return;
        };
        defer allocator.free(source);
        try transpileAll(io, allocator, source, "main");
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
        return cmdUpgrade(io, allocator);
    }

    // Parse flags
    var target: Target = .all;
    var input_path: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var explicit_target = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-target") and i + 1 < args.len) {
            i += 1;
            explicit_target = true;
            if (std.mem.eql(u8, args[i], "cpp")) target = .cpp
            else if (std.mem.eql(u8, args[i], "js")) target = .js
            else target = .c;
        } else if (input_path == null) {
            input_path = args[i];
        } else {
            output_path = args[i];
        }
    }
    // If an output path is given but no explicit target, infer single-target C
    if (!explicit_target and output_path != null) target = .c;

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
        .all => {
            // Derive basename and directory prefix from input path
            var basename: []const u8 = in_path;
            var dir_prefix: []const u8 = "";
            if (std.mem.lastIndexOfScalar(u8, in_path, '/')) |sep| {
                dir_prefix = in_path[0 .. sep + 1];
                basename = in_path[sep + 1 ..];
            }
            if (std.mem.endsWith(u8, basename, ".ts")) basename = basename[0 .. basename.len - 3];
            try transpileAllParsed(io, allocator, &parser, &checker, root, basename, dir_prefix);
        },
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
                for (files) |file| {
                    std.debug.print("// === {s} ===\n{s}\n", .{ file.name, file.content });
                }
            }
        },
    }
}

/// Transpile source to all 4 targets (.h, .c, .cpp, .js) and write to cwd.
fn transpileAll(io: std.Io, allocator: std.mem.Allocator, source: []const u8, basename: []const u8) !void {
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
    var checker = Checker.init(&parser.tree, allocator);
    defer checker.deinit();
    try checker.check(root);
    try transpileAllParsed(io, allocator, &parser, &checker, root, basename, "");
}

fn transpileAllParsed(io: std.Io, allocator: std.mem.Allocator, parser: *Parser, checker: *Checker, root: NodeIndex, basename: []const u8, dir_prefix: []const u8) !void {
    const cwd = std.Io.Dir.cwd();

    // JS
    var js_gen = CodeGenJS.init(&parser.tree, allocator);
    defer js_gen.deinit();
    const js_source = try js_gen.generate(root);
    const js_name = try std.fmt.allocPrint(allocator, "{s}{s}.js", .{ dir_prefix, basename });
    defer allocator.free(js_name);
    cwd.writeFile(io, .{ .sub_path = js_name, .data = js_source }) catch {
        std.debug.print("error: cannot write '{s}'\n", .{js_name});
        return error.WriteError;
    };
    std.debug.print("wrote {s} ({d} bytes)\n", .{ js_name, js_source.len });

    // Unified .h + .cpp + .c
    var cpp_gen = CodeGenCpp.init(&parser.tree, checker, allocator);
    defer cpp_gen.deinit();
    const files = try cpp_gen.generateUnified(root, basename);
    for (files) |file| {
        const out_path = if (dir_prefix.len > 0)
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ dir_prefix, file.name })
        else
            file.name;
        defer if (dir_prefix.len > 0) allocator.free(out_path);
        cwd.writeFile(io, .{ .sub_path = out_path, .data = file.content }) catch {
            std.debug.print("error: cannot write '{s}'\n", .{out_path});
            return error.WriteError;
        };
        std.debug.print("wrote {s} ({d} bytes)\n", .{ out_path, file.content.len });
    }
}
