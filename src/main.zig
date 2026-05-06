const std = @import("std");
const Parser = @import("parser.zig").Parser;
const Checker = @import("checker.zig").Checker;
const CodeGen = @import("codegen.zig").CodeGen;

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
        std.debug.print("usage: zigtsc <input.ts> [output.c]\n", .{});
        return error.MissingArgument;
    }

    const input_path = args[0];
    const cwd = std.Io.Dir.cwd();
    const source = cwd.readFileAlloc(io, input_path, allocator, .unlimited) catch {
        std.debug.print("error: cannot read '{s}'\n", .{input_path});
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

    // Generate C
    var codegen = CodeGen.init(&parser.tree, &checker, allocator);
    defer codegen.deinit();
    const c_source = try codegen.generate(root);

    // Output
    if (args.len >= 2) {
        const output_path = args[1];
        cwd.writeFile(io, .{ .sub_path = output_path, .data = c_source }) catch {
            std.debug.print("error: cannot write '{s}'\n", .{output_path});
            return error.WriteError;
        };
        std.debug.print("wrote {s} ({d} bytes)\n", .{ output_path, c_source.len });
    } else {
        std.debug.print("{s}", .{c_source});
    }
}
