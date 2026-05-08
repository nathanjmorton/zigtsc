const std = @import("std");
const zigc = @import("zigc");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGenJS = @import("codegen_js.zig").CodeGenJS;
const CodeGenCpp = @import("codegen_cpp.zig").CodeGenCpp;

// ── Version ───────────────────────────────────────────────────────────────────

const VERSION = "0.5.0";

const HELP_TEXT =
    \\zigtsc — TypeScript subset → C / C++ / JS transpiler & compiler
    \\
    \\Usage:
    \\  zigtsc init <directory>                # scaffold project with src/main.ts
    \\  zigtsc transpile <input.ts>            # transpile → src/zigtscout/
    \\  zigtsc compile <zigtscout-dir>         # compile → zig-out/bin + zig-out/wasm
    \\  zigtsc upgrade                         # upgrade to latest release
    \\
    \\Workflow:
    \\  zigtsc init myapp && cd myapp
    \\  zigtsc transpile src/main.ts
    \\  zigtsc compile src/zigtscout
    \\
    \\Docs:   https://zigtsc.nathanjmorton.com/docs
    \\GitHub: https://github.com/nathanjmorton/zigtsc
    \\
;

const INIT_TEMPLATE =
    \\// zigtsc starter
    \\//
    \\// Transpile:  zigtsc transpile src/main.ts
    \\// Compile:    zigtsc compile src/zigtscout
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

const COMPILE_BUILD_ZIG =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    // Shared settings for both targets
    \\    const common_mod = b.createModule(.{
    \\        .optimize = optimize,
    \\        .link_libc = true,
    \\        .link_libcpp = true,
    \\    });
    \\
    \\    common_mod.addIncludePath(b.path("ZIGTSCOUT_DIR"));
    \\
    \\    // Add C and C++ sources
    \\    common_mod.addCSourceFiles(.{
    \\        .root = b.path("ZIGTSCOUT_DIR"),
    \\        .files = &.{"PROJ_NAME.c"},
    \\        .flags = &.{ "-std=c11", "-Wall", "-Wextra" },
    \\    });
    \\    common_mod.addCSourceFiles(.{
    \\        .root = b.path("ZIGTSCOUT_DIR"),
    \\        .files = &.{"PROJ_NAME.cpp"},
    \\        .flags = &.{ "-std=c++17", "-Wall", "-Wextra" },
    \\    });
    \\
    \\    // === Native ===
    \\    const native_mod = b.createModule(.{
    \\        .target = b.graph.host,
    \\        .optimize = optimize,
    \\        .link_libc = true,
    \\        .link_libcpp = true,
    \\    });
    \\    native_mod.addIncludePath(b.path("ZIGTSCOUT_DIR"));
    \\    native_mod.addCSourceFiles(.{ .root = b.path("ZIGTSCOUT_DIR"), .files = &.{"PROJ_NAME.c"} });
    \\    native_mod.addCSourceFiles(.{ .root = b.path("ZIGTSCOUT_DIR"), .files = &.{"PROJ_NAME.cpp"} });
    \\
    \\    const exe = b.addExecutable(.{
    \\        .name = "PROJ_NAME",
    \\        .root_module = native_mod,
    \\    });
    \\    b.installArtifact(exe);
    \\
    \\    // === Wasm (WASI) - installed to zig-out/wasm/ ===
    \\    const wasm_mod = b.createModule(.{
    \\        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi }),
    \\        .optimize = optimize,
    \\        .link_libc = true,
    \\        .link_libcpp = true,
    \\    });
    \\    wasm_mod.addIncludePath(b.path("ZIGTSCOUT_DIR"));
    \\    wasm_mod.addCSourceFiles(.{ .root = b.path("ZIGTSCOUT_DIR"), .files = &.{"PROJ_NAME.c"} });
    \\    wasm_mod.addCSourceFiles(.{ .root = b.path("ZIGTSCOUT_DIR"), .files = &.{"PROJ_NAME.cpp"} });
    \\
    \\    const wasm = b.addExecutable(.{
    \\        .name = "PROJ_NAME",
    \\        .root_module = wasm_mod,
    \\    });
    \\
    \\    // Install Wasm into zig-out/wasm/ subfolder
    \\    const wasm_install = b.addInstallArtifact(wasm, .{
    \\        .dest_dir = .{ .override = .{ .custom = "wasm" } },
    \\    });
    \\    b.getInstallStep().dependOn(&wasm_install.step);
    \\
    \\    // Run step (native only)
    \\    const run_cmd = b.addRunArtifact(exe);
    \\    run_cmd.step.dependOn(b.getInstallStep());
    \\    if (b.args) |args| run_cmd.addArgs(args);
    \\    const run_step = b.step("run", "Run the native app");
    \\    run_step.dependOn(&run_cmd.step);
    \\}
    \\
;

const COMPILE_BUILD_ZIG_ZON =
    \\.{
    \\    .name = .PROJ_IDENT,
    \\    .version = "0.1.0",
    \\    .minimum_zig_version = "0.16.0",
    \\    .paths = .{
    \\        "build.zig",
    \\        "build.zig.zon",
    \\        "src",
    \\    },
    \\    .dependencies = .{},
    \\}
    \\
;

// ── init ─────────────────────────────────────────────────────────────────────

fn runInit(io: std.Io, dir: []const u8) !void {
    const cwd = std.Io.Dir.cwd();

    var src_dir_buf: [512]u8 = undefined;
    const src_dir_path = if (std.mem.eql(u8, dir, "."))
        "src"
    else blk: {
        const len = (std.fmt.bufPrint(&src_dir_buf, "{s}/src", .{dir}) catch return error.PathTooLong).len;
        break :blk src_dir_buf[0..len];
    };
    cwd.createDirPath(io, src_dir_path) catch {};

    var ts_path_buf: [512]u8 = undefined;
    const ts_path = if (std.mem.eql(u8, dir, "."))
        "src/main.ts"
    else blk: {
        const len = (std.fmt.bufPrint(&ts_path_buf, "{s}/src/main.ts", .{dir}) catch return error.PathTooLong).len;
        break :blk ts_path_buf[0..len];
    };

    cwd.writeFile(io, .{ .sub_path = ts_path, .data = INIT_TEMPLATE }) catch {
        std.debug.print("error: cannot write '{s}'\n", .{ts_path});
        return error.WriteError;
    };

    std.debug.print("created {s}\n\n", .{ts_path});
    std.debug.print("next steps:\n", .{});
    if (!std.mem.eql(u8, dir, ".")) {
        std.debug.print("  cd {s}\n", .{dir});
    }
    std.debug.print("  zigtsc transpile src/main.ts       # transpile -> src/zigtscout/\n", .{});
    std.debug.print("  zigtsc compile src/zigtscout       # compile  -> zig-out/bin + zig-out/wasm\n", .{});
}

// ── transpile ────────────────────────────────────────────────────────────────

fn runTranspile(io: std.Io, gpa: std.mem.Allocator, in_path: []const u8) !void {
    const cwd = std.Io.Dir.cwd();

    // Read source file
    const source = cwd.readFileAlloc(io, in_path, gpa, .unlimited) catch {
        std.debug.print("error: cannot read '{s}'\n", .{in_path});
        return error.FileNotFound;
    };
    defer gpa.free(source);

    // Derive basename from input filename
    var basename: []const u8 = in_path;
    if (std.mem.lastIndexOfScalar(u8, in_path, '/')) |sep| {
        basename = in_path[sep + 1 ..];
    }
    if (std.mem.endsWith(u8, basename, ".ts")) {
        basename = basename[0 .. basename.len - 3];
    }

    // Parse
    var parser = Parser.init(source, gpa);
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
    var checker = Checker.init(&parser.tree, gpa);
    defer checker.deinit();
    try checker.check(root);

    // Write transpiled output to src/zigtscout/
    const out_dir = "src/zigtscout";
    cwd.createDirPath(io, out_dir) catch {};

    // JS output
    var js_gen = CodeGenJS.init(&parser.tree, gpa);
    defer js_gen.deinit();
    const js_source = try js_gen.generate(root);
    const js_path = try std.fmt.allocPrint(gpa, "{s}/{s}.js", .{ out_dir, basename });
    defer gpa.free(js_path);

    cwd.writeFile(io, .{ .sub_path = js_path, .data = js_source }) catch {
        std.debug.print("error: cannot write '{s}'\n", .{js_path});
        return error.WriteError;
    };
    std.debug.print("wrote {s} ({d} bytes)\n", .{ js_path, js_source.len });

    // Unified .h + .cpp + .c
    var cpp_gen = CodeGenCpp.init(&parser.tree, &checker, gpa);
    defer cpp_gen.deinit();
    const files = try cpp_gen.generateUnified(root, basename);
    defer {
        for (files) |file| {
            gpa.free(file.name);
            gpa.free(file.content);
        }
        gpa.free(files);
    }

    for (files) |file| {
        const out_path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ out_dir, file.name });
        defer gpa.free(out_path);

        cwd.writeFile(io, .{ .sub_path = out_path, .data = file.content }) catch {
            std.debug.print("error: cannot write '{s}'\n", .{out_path});
            return error.WriteError;
        };
        std.debug.print("wrote {s} ({d} bytes)\n", .{ out_path, file.content.len });
    }
}

// ── compile ──────────────────────────────────────────────────────────────────

fn runCompile(io: std.Io, gpa: std.mem.Allocator, zigtscout_dir: []const u8) !void {
    const cwd = std.Io.Dir.cwd();

    // Validate the zigtscout directory exists
    var dir = cwd.openDir(io, zigtscout_dir, .{ .iterate = true }) catch {
        std.debug.print("error: cannot open '{s}' -- did you run 'zigtsc transpile' first?\n", .{zigtscout_dir});
        return error.FileNotFound;
    };
    defer dir.close(io);

    // Scan for .c file to determine the project basename
    var name_buf: ?[]u8 = null;
    defer if (name_buf) |buf| gpa.free(buf);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind == .directory) continue;
        if (std.mem.endsWith(u8, entry.name, ".c") and !std.mem.endsWith(u8, entry.name, ".cpp")) {
            name_buf = try gpa.dupe(u8, entry.name[0 .. entry.name.len - 2]);
            break;
        }
    }

    const name = name_buf orelse {
        std.debug.print("error: no .c file found in '{s}'\n", .{zigtscout_dir});
        return error.FileNotFound;
    };

    // Make a valid Zig identifier from the name (replace hyphens, etc.)
    const ident = try gpa.dupe(u8, name);
    defer gpa.free(ident);
    for (ident) |*ch| {
        if (ch.* == '-') ch.* = '_';
    }

    // Generate build.zig from template
    {
        const with_dir = try zigc.replaceAll(gpa, COMPILE_BUILD_ZIG, "ZIGTSCOUT_DIR", zigtscout_dir);
        defer gpa.free(with_dir);

        const build_zig = try zigc.replaceAll(gpa, with_dir, "PROJ_NAME", name);
        defer gpa.free(build_zig);

        cwd.writeFile(io, .{ .sub_path = "build.zig", .data = build_zig }) catch {
            std.debug.print("error: cannot write 'build.zig'\n", .{});
            return error.WriteError;
        };
    }

    // Generate build.zig.zon from template
    {
        const build_zig_zon = try zigc.replaceAll(gpa, COMPILE_BUILD_ZIG_ZON, "PROJ_IDENT", ident);
        defer gpa.free(build_zig_zon);

        cwd.writeFile(io, .{ .sub_path = "build.zig.zon", .data = build_zig_zon }) catch {
            std.debug.print("error: cannot write 'build.zig.zon'\n", .{});
            return error.WriteError;
        };
    }

    // Build both native and Wasm
    std.debug.print("Building native + wasm...\n", .{});
    try zigc.execZig(io, gpa, &.{ "zig", "build" });

    std.debug.print("\n✅ Build successful!\n", .{});
    std.debug.print("   Native:   zig-out/bin/{s}\n", .{name});
    std.debug.print("   Wasm:     zig-out/wasm/{s}.wasm\n\n", .{name});

    std.debug.print("Run with:\n", .{});
    std.debug.print("   zigtsc run zig-out/bin/{s}\n", .{name});
    std.debug.print("   zigtsc run zig-out/wasm/{s}.wasm\n", .{name});
}

// ── run ──────────────────────────────────────────────────────────────────
fn runBinary(gpa: std.mem.Allocator, path: []const u8, io: std.Io) !void {
    if (std.mem.endsWith(u8, path, ".wasm")) {
        std.debug.print("Running Wasm module with wasmtime...\n", .{});

        const result = std.process.run(gpa, io, .{
            .argv = &.{ "wasmtime", path },
        }) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("error: 'wasmtime' command not found in PATH.\n", .{});
                std.debug.print("   Install with: brew install wasmtime\n", .{});
                return;
            }
            return err;
        };
        defer {
            gpa.free(result.stdout);
            gpa.free(result.stderr);
        }

        std.debug.print("{s}", .{result.stdout});
        if (result.stderr.len > 0) {
            std.debug.print("{s}", .{result.stderr});
        }
        return;
    }

    // Native binary - direct execution
    std.debug.print("Running native binary: {s}\n", .{path});

    var child = try std.process.spawn(io, .{
        .argv = &.{path},
    });
    _ = try child.wait(io); // ← fixed: now passes io
}

// ── main ─────────────────────────────────────────────────────────────────────

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa; // ← changed from .allocator
    const io = init.io;

    // Collect args (skip argv[0])
    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(gpa);
    var it = std.process.Args.Iterator.init(init.minimal.args);
    _ = it.skip();
    while (it.next()) |arg| try args_list.append(gpa, arg);
    const args = args_list.items;

    if (args.len < 1) {
        std.debug.print("{s}", .{HELP_TEXT});
        return;
    }

    // help
    if (std.mem.eql(u8, args[0], "help") or std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h")) {
        std.debug.print("{s}", .{HELP_TEXT});
        return;
    }

    // init
    if (std.mem.eql(u8, args[0], "init")) {
        const dir = if (args.len > 1) args[1] else ".";
        return runInit(io, dir);
    }

    // transpile
    if (std.mem.eql(u8, args[0], "transpile")) {
        if (args.len < 2) {
            std.debug.print("error: missing input file\nUsage: zigtsc transpile <input.ts>\n", .{});
            return error.MissingArgument;
        }
        return runTranspile(io, gpa, args[1]);
    }

    // compile
    if (std.mem.eql(u8, args[0], "compile")) {
        if (args.len < 2) {
            std.debug.print("error: missing zigtscout directory\nUsage: zigtsc compile <zigtscout-dir>\n", .{});
            return error.MissingArgument;
        }
        return runCompile(io, gpa, args[1]);
    }

    // upgrade
    if (std.mem.eql(u8, args[0], "upgrade")) {
        return zigc.cmdUpgrade(io, gpa, "zigtsc", VERSION, "nathanjmorton/zigtsc");
    }

    // run
    if (std.mem.eql(u8, args[0], "run")) {
        if (args.len < 2) {
            std.debug.print("usage: zigtsc run <path-to-binary-or-wasm>\n", .{});
            return;
        }
        return runBinary(gpa, args[1], io);
    }

    std.debug.print("error: unknown command '{s}'\n", .{args[0]});
    std.debug.print("{s}", .{HELP_TEXT});
    return error.UnknownCommand;
}
