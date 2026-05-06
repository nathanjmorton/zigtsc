const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGen = @import("codegen.zig").CodeGen;
const CodeGenJS = @import("codegen_js.zig").CodeGenJS;
const CodeGenCpp = @import("codegen_cpp.zig").CodeGenCpp;

const Target = enum { c, cpp, js };

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    // Collect args (skip argv[0])
    var args_list: std.ArrayList([]const u8) = .empty;
    defer args_list.deinit(allocator);
    var it = std.process.Args.Iterator.init(init.minimal.args);
    _ = it.skip();
    while (it.next()) |arg| try args_list.append(allocator, arg);
    const args = args_list.items;

    if (args.len < 1) {
        std.debug.print("usage: zigtsc <input.ts> [output] [-target c|cpp|js]\n", .{});
        return error.MissingArgument;
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
        std.debug.print("usage: zigtsc <input.ts> [output] [-target c|cpp|js]\n", .{});
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
