const std = @import("std");
const zigc = @import("zigc");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGenJS = @import("codegen_js.zig").CodeGenJS;
const CodeGenCpp = @import("codegen_cpp.zig").CodeGenCpp;
const CodeGenCuda = @import("codegen_cuda.zig").CodeGenCuda;
const ast_mod = @import("ast.zig");
const unpackStringRef = ast_mod.unpackStringRef;

// ── Version ───────────────────────────────────────────────────────────────────

const VERSION = "0.14.0";

const HELP_TEXT =
    \\zigtsc — TypeScript subset → C / C++ / JS transpiler & compiler
    \\
    \\Usage:
    \\  zigtsc init <directory>                # scaffold project with src/main.ts
    \\  zigtsc transpile <input.ts>            # transpile → src/zigtscout/
    \\  zigtsc compile <zigtscout-dir>         # compile → zig-out/bin + zig-out/wasm
    \\  zigtsc run <binary-or-wasm>            # run native binary or wasm module
    \\  zigtsc version                         # print version
    \\  zigtsc upgrade                         # upgrade to latest release
    \\
    \\Quickstart:
    \\  zigtsc init demo
    \\  zigtsc transpile demo/src/main.ts
    \\  zigtsc compile demo/src/zigtscout
    \\  zigtsc run demo/zig-out/bin/main
    \\  zigtsc run demo/zig-out/wasm/main.wasm
    \\
    \\Docs:   https://zigtsc.nathanjmorton.com/docs
    \\GitHub: https://github.com/nathanjmorton/zigtsc
    \\
;

const MATH_TEMPLATE =
    \\// math.ts — basic arithmetic helpers
    \\
    \\export function add(a: i32, b: i32): i32 {
    \\    return a + b;
    \\}
    \\
    \\export function subtract(a: i32, b: i32): i32 {
    \\    return a - b;
    \\}
    \\
;

const COUNTER_TEMPLATE =
    \\// counter.ts — exported Counter class
    \\
    \\import { add, subtract } from './math';
    \\
    \\export class Counter {
    \\    value: i32;
    \\
    \\    constructor(init: i32) {
    \\        this.value = init;
    \\    }
    \\
    \\    increment(): void {
    \\        this.value = add(this.value, 1);
    \\    }
    \\
    \\    decrement(): void {
    \\        this.value = subtract(this.value, 1);
    \\    }
    \\
    \\    getVal(): i32 {
    \\        return this.value;
    \\    }
    \\}
    \\
;

const INIT_TEMPLATE =
    \\// zigtsc starter — recursive ESM multi-file example
    \\//
    \\// Transpile:  zigtsc transpile src/main.ts
    \\// Compile:    zigtsc compile src/zigtscout
    \\
    \\import { Counter } from './counter';
    \\
    \\interface Point {
    \\    x: number;
    \\    y: number;
    \\}
    \\
    \\function distance(a: Point, b: Point): number {
    \\    let dx: number = b.x - a.x;
    \\    let dy: number = b.y - a.y;
    \\    return dx * dx + dy * dy;
    \\}
    \\
    \\const p1: Point = { x: 0, y: 0 };
    \\const p2: Point = { x: 3, y: 4 };
    \\console.log(distance(p1, p2));
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
    \\    common_mod.addIncludePath(.{ .cwd_relative = "ZIGTSCOUT_DIR" });
    \\
    \\    // Add C and C++ sources
    \\    common_mod.addCSourceFiles(.{
    \\        .root = .{ .cwd_relative = "ZIGTSCOUT_DIR" },
    \\        .files = &.{"PROJ_NAME.c"},
    \\        .flags = &.{ "-std=c11", "-Wall", "-Wextra" },
    \\    });
    \\    common_mod.addCSourceFiles(.{
    \\        .root = .{ .cwd_relative = "ZIGTSCOUT_DIR" },
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
    \\    native_mod.addIncludePath(.{ .cwd_relative = "ZIGTSCOUT_DIR" });
    \\    native_mod.addCSourceFiles(.{ .root = .{ .cwd_relative = "ZIGTSCOUT_DIR" }, .files = &.{"PROJ_NAME.c"} });
    \\    native_mod.addCSourceFiles(.{ .root = .{ .cwd_relative = "ZIGTSCOUT_DIR" }, .files = &.{"PROJ_NAME.cpp"} });
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
    \\    wasm_mod.addIncludePath(.{ .cwd_relative = "ZIGTSCOUT_DIR" });
    \\    wasm_mod.addCSourceFiles(.{ .root = .{ .cwd_relative = "ZIGTSCOUT_DIR" }, .files = &.{"PROJ_NAME.c"} });
    \\    wasm_mod.addCSourceFiles(.{ .root = .{ .cwd_relative = "ZIGTSCOUT_DIR" }, .files = &.{"PROJ_NAME.cpp"} });
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

    // Write counter.ts alongside main.ts
    var counter_path_buf: [512]u8 = undefined;
    const counter_path = if (std.mem.eql(u8, dir, "."))
        "src/counter.ts"
    else blk: {
        const len = (std.fmt.bufPrint(&counter_path_buf, "{s}/src/counter.ts", .{dir}) catch return error.PathTooLong).len;
        break :blk counter_path_buf[0..len];
    };
    cwd.writeFile(io, .{ .sub_path = counter_path, .data = COUNTER_TEMPLATE }) catch {
        std.debug.print("error: cannot write '{s}'\n", .{counter_path});
        return error.WriteError;
    };

    // Write math.ts alongside counter.ts
    var math_path_buf: [512]u8 = undefined;
    const math_path = if (std.mem.eql(u8, dir, "."))
        "src/math.ts"
    else blk: {
        const len = (std.fmt.bufPrint(&math_path_buf, "{s}/src/math.ts", .{dir}) catch return error.PathTooLong).len;
        break :blk math_path_buf[0..len];
    };
    cwd.writeFile(io, .{ .sub_path = math_path, .data = MATH_TEMPLATE }) catch {
        std.debug.print("error: cannot write '{s}'\n", .{math_path});
        return error.WriteError;
    };

    std.debug.print("created {s}\n", .{ts_path});
    std.debug.print("created {s}\n", .{counter_path});
    std.debug.print("created {s}\n\n", .{math_path});
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

    // Derive directory of input file for resolving relative imports
    const in_dir: []const u8 = if (std.mem.lastIndexOfScalar(u8, in_path, '/'))
        |sep| in_path[0..sep]
    else
        ".";

    // Parse main file
    var parser = Parser.init(source, gpa);
    defer parser.deinit();
    const root = try parser.parse();

    if (parser.errors.items.len > 0) {
        for (parser.errors.items) |err| {
            const loc_str = source[err.loc.start..@min(err.loc.end, source.len)];
            std.debug.print("error: {s} at '{s}'\n", .{ err.msg, loc_str });
        }
        parser.tree.deinit();
        return error.ParseError;
    }

    // ── Recursive import resolution (worklist) ────────────────────────────
    // Walk imports transitively: main → A → B → ... deduplicating by path.
    // Collected sources are kept in dependency order (deepest-first).

    var import_sources: std.ArrayList([]const u8) = .empty;
    defer {
        for (import_sources.items) |s| gpa.free(s);
        import_sources.deinit(gpa);
    }

    // Set of already-resolved paths to avoid duplicates / cycles
    var visited: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var vit = visited.iterator();
        while (vit.next()) |entry| gpa.free(@constCast(entry.key_ptr.*));
        visited.deinit(gpa);
    }

    // Seed the worklist with imports from the main file
    var worklist: std.ArrayList(WorkItem) = .empty;
    defer {
        for (worklist.items) |w| gpa.free(w.resolved_path);
        worklist.deinit(gpa);
    }
    try extractImports(&parser.tree, root, in_dir, gpa, &worklist);

    // Process worklist — each item may add more items
    while (worklist.items.len > 0) {
        const item = worklist.orderedRemove(0);
        defer gpa.free(item.resolved_path);

        // Skip if already visited
        if (visited.get(item.resolved_path) != null) continue;

        // Mark visited (own the key)
        const key = try gpa.dupe(u8, item.resolved_path);
        try visited.put(gpa, key, {});

        // Read the imported file
        const imp_source = cwd.readFileAlloc(io, item.resolved_path, gpa, .unlimited) catch {
            std.debug.print("error: cannot read imported module '{s}'\n", .{item.resolved_path});
            return error.FileNotFound;
        };

        // Parse it to discover its own imports
        var imp_parser = Parser.init(imp_source, gpa);
        const imp_root = try imp_parser.parse();

        if (imp_parser.errors.items.len > 0) {
            for (imp_parser.errors.items) |err| {
                const loc_str = imp_source[err.loc.start..@min(err.loc.end, imp_source.len)];
                std.debug.print("error: {s} at '{s}' in '{s}'\n", .{ err.msg, loc_str, item.resolved_path });
            }
            imp_parser.tree.deinit();
            imp_parser.deinit();
            gpa.free(imp_source);
            return error.ParseError;
        }

        // Derive directory of this imported file for resolving its own imports
        const imp_dir: []const u8 = if (std.mem.lastIndexOfScalar(u8, item.resolved_path, '/'))
            |sep| item.resolved_path[0..sep]
        else
            ".";

        // Add any imports from this file to the worklist
        try extractImports(&imp_parser.tree, imp_root, imp_dir, gpa, &worklist);

        imp_parser.tree.deinit();
        imp_parser.deinit();

        // Keep the source for merging
        try import_sources.append(gpa, imp_source);
    }

    // ── Build merged source and re-parse ─────────────────────────────────
    var final_tree: *ast_mod.Ast = &parser.tree;
    var merged_parser: ?Parser = null;
    var merged_source_alloc: ?[]const u8 = null;
    defer {
        if (merged_parser) |*mp| {
            mp.tree.deinit();
            mp.deinit();
        } else {
            parser.tree.deinit();
        }
        if (merged_source_alloc) |ms| gpa.free(ms);
    }

    var final_root = root;

    if (import_sources.items.len > 0) {
        var merged: std.ArrayList(u8) = .empty;
        defer merged.deinit(gpa);

        // Prepend all imported file contents (dependency order)
        for (import_sources.items) |imp_src| {
            try merged.appendSlice(gpa, imp_src);
            try merged.append(gpa, '\n');
        }

        // Append main source (import_decl nodes are skipped by codegen)
        try merged.appendSlice(gpa, source);

        merged_source_alloc = try gpa.dupe(u8, merged.items);

        merged_parser = Parser.init(merged_source_alloc.?, gpa);
        final_root = try merged_parser.?.parse();

        if (merged_parser.?.errors.items.len > 0) {
            for (merged_parser.?.errors.items) |err| {
                const ms = merged_source_alloc.?;
                const loc_str = ms[err.loc.start..@min(err.loc.end, ms.len)];
                std.debug.print("error: {s} at '{s}'\n", .{ err.msg, loc_str });
            }
            return error.ParseError;
        }

        parser.tree.deinit();
        final_tree = &merged_parser.?.tree;
    }

    // Type check
    var checker = Checker.init(final_tree, gpa);
    defer checker.deinit();
    try checker.check(final_root);

    // Write transpiled output to <input_dir>/zigtscout/
    var out_dir_buf: [512]u8 = undefined;
    const out_dir = blk: {
        const parent = if (std.mem.lastIndexOfScalar(u8, in_path, '/'))
            |sep| in_path[0..sep]
        else
            ".";
        const len = (std.fmt.bufPrint(&out_dir_buf, "{s}/zigtscout", .{parent}) catch return error.PathTooLong).len;
        break :blk out_dir_buf[0..len];
    };
    cwd.createDirPath(io, out_dir) catch {};

    // JS output
    var js_gen = CodeGenJS.init(final_tree, gpa);
    defer js_gen.deinit();
    const js_source = try js_gen.generate(final_root);
    const js_path = try std.fmt.allocPrint(gpa, "{s}/{s}.js", .{ out_dir, basename });
    defer gpa.free(js_path);

    cwd.writeFile(io, .{ .sub_path = js_path, .data = js_source }) catch {
        std.debug.print("error: cannot write '{s}'\n", .{js_path});
        return error.WriteError;
    };
    std.debug.print("wrote {s} ({d} bytes)\n", .{ js_path, js_source.len });

    // Unified .h + .cpp + .c
    var cpp_gen = CodeGenCpp.init(final_tree, &checker, gpa);
    defer cpp_gen.deinit();
    const files = try cpp_gen.generateUnified(final_root, basename);
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

    // CUDA output (only if source contains kernel declarations)
    var cuda_gen = CodeGenCuda.init(final_tree, &checker, gpa);
    defer cuda_gen.deinit();
    const cuda_source = try cuda_gen.generate(final_root);
    if (std.mem.indexOf(u8, cuda_source, "__global__") != null) {
        const cu_path = try std.fmt.allocPrint(gpa, "{s}/{s}.cu", .{ out_dir, basename });
        defer gpa.free(cu_path);

        cwd.writeFile(io, .{ .sub_path = cu_path, .data = cuda_source }) catch {
            std.debug.print("error: cannot write '{s}'\n", .{cu_path});
            return error.WriteError;
        };
        std.debug.print("wrote {s} ({d} bytes)\n", .{ cu_path, cuda_source.len });
    }
}

// ── import resolution helpers ────────────────────────────────────────────────

const WorkItem = struct { resolved_path: []const u8 };

/// Walk a parsed program's top-level statements and append a WorkItem for
/// each `import_decl`, resolving the module path relative to `base_dir`.
fn extractImports(
    tree: *const ast_mod.Ast,
    root: ast_mod.NodeIndex,
    base_dir: []const u8,
    alloc: std.mem.Allocator,
    worklist: *std.ArrayList(WorkItem),
) !void {
    const node = tree.nodes.items[root];
    if (node.tag != .program) return;
    const start = node.data.lhs;
    const count = node.data.rhs;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const s = tree.nodes.items[tree.extra.items[start + i]];
        if (s.tag == .import_decl) {
            const mod_path = tree.getString(unpackStringRef(s.data.lhs));
            var clean = mod_path;
            if (std.mem.startsWith(u8, clean, "./")) clean = clean[2..];
            const resolved = try std.fmt.allocPrint(alloc, "{s}/{s}.ts", .{ base_dir, clean });
            try worklist.append(alloc, .{ .resolved_path = resolved });
        }
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

    // Resolve zigtscout_dir to an absolute path NOW, before any setCurrentDir.
    // The generated build.zig uses .cwd_relative which is evaluated relative to
    // whatever the process CWD is when `zig build` runs, so it must be absolute.
    const abs_zigtscout_dir: []const u8 = blk: {
        if (std.fs.path.isAbsolute(zigtscout_dir)) {
            break :blk try gpa.dupe(u8, zigtscout_dir);
        }
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const raw = std.c.getcwd(&buf, buf.len) orelse return error.GetCwdFailed;
        const cwd_str = std.mem.sliceTo(raw, 0);
        break :blk try std.fmt.allocPrint(gpa, "{s}/{s}", .{ cwd_str, zigtscout_dir });
    };
    defer gpa.free(abs_zigtscout_dir);

    // Derive the project root (2 levels up from zigtscout_dir: zigtscout -> src -> project root)
    // so build.zig and zig-out/ land in the demo project, not in the zigtsc source tree.
    var src_dir = dir.openDir(io, "..", .{}) catch {
        std.debug.print("error: cannot open parent of '{s}'\n", .{zigtscout_dir});
        return error.FileNotFound;
    };
    defer src_dir.close(io);
    var project_root_dir = src_dir.openDir(io, "..", .{}) catch {
        std.debug.print("error: cannot open project root from '{s}'\n", .{zigtscout_dir});
        return error.FileNotFound;
    };
    defer project_root_dir.close(io);

    // Generate build.zig from template — written into the project root
    {
        const with_dir = try zigc.replaceAll(gpa, COMPILE_BUILD_ZIG, "ZIGTSCOUT_DIR", abs_zigtscout_dir);
        defer gpa.free(with_dir);

        const build_zig = try zigc.replaceAll(gpa, with_dir, "PROJ_NAME", name);
        defer gpa.free(build_zig);

        project_root_dir.writeFile(io, .{ .sub_path = "build.zig", .data = build_zig }) catch {
            std.debug.print("error: cannot write 'build.zig'\n", .{});
            return error.WriteError;
        };
    }

    // Generate build.zig.zon from template — written into the project root
    {
        const build_zig_zon = try zigc.replaceAll(gpa, COMPILE_BUILD_ZIG_ZON, "PROJ_IDENT", ident);
        defer gpa.free(build_zig_zon);

        project_root_dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = build_zig_zon }) catch {
            std.debug.print("error: cannot write 'build.zig.zon'\n", .{});
            return error.WriteError;
        };
    }

    // Change CWD to the project root so `zig build` outputs zig-out/ there
    // and execZig's fingerprint helper reads the correct build.zig.zon.
    try std.process.setCurrentDir(io, project_root_dir);

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

    // version
    if (std.mem.eql(u8, args[0], "version") or std.mem.eql(u8, args[0], "--version") or std.mem.eql(u8, args[0], "-v")) {
        std.debug.print("{s}\n", .{VERSION});
        return;
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
