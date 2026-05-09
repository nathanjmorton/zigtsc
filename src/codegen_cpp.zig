const std = @import("std");
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;
const NodeIndex = ast_mod.NodeIndex;
const null_node = ast_mod.null_node;
const Op = ast_mod.Op;
const unpackStringRef = ast_mod.unpackStringRef;
const Checker = @import("checker.zig").Checker;

pub const OutputFile = struct {
    name: []const u8,
    content: []const u8,
};

const ClassVar = struct { name: []const u8, class_name: []const u8 };

pub const CodeGenCpp = struct {
    tree: *const ast_mod.Ast,
    checker: *const Checker,
    out: std.ArrayList(u8) = .empty,
    indent: u32 = 0,
    allocator: std.mem.Allocator,
    in_method: bool = false,
    bridge_mode: bool = false,
    class_vars: std.ArrayList(ClassVar) = .empty,

    pub fn init(tree: *const ast_mod.Ast, checker: *const Checker, allocator: std.mem.Allocator) CodeGenCpp {
        return .{ .tree = tree, .checker = checker, .allocator = allocator };
    }

    pub fn deinit(self: *CodeGenCpp) void {
        self.out.deinit(self.allocator);
        self.class_vars.deinit(self.allocator);
    }

    /// Generate multi-file output: returns list of OutputFile (name + content).
    /// Caller must free each content slice and the OutputFile slice itself.
    pub fn generate(self: *CodeGenCpp, root: NodeIndex) ![]OutputFile {
        const node = self.tree.nodes.items[root];
        if (node.tag != .program) return &[_]OutputFile{};
        const start = node.data.lhs;
        const count = node.data.rhs;

        var files: std.ArrayList(OutputFile) = .empty;
        defer files.deinit(self.allocator);

        // Collect class names for include resolution
        var class_names: std.ArrayList([]const u8) = .empty;
        defer class_names.deinit(self.allocator);
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start + i]];
            if (s.tag == .class_decl) try class_names.append(self.allocator, self.tree.getString(unpackStringRef(s.data.lhs)));
        }

        // Generate header + impl for each class
        i = 0;
        while (i < count) : (i += 1) {
            const idx = self.tree.extra.items[start + i];
            const s = self.tree.nodes.items[idx];
            if (s.tag == .class_decl) {
                const cname = self.tree.getString(unpackStringRef(s.data.lhs));

                // Generate header
                self.out.clearRetainingCapacity();
                self.indent = 0;
                try self.emitClassHeader(s, class_names.items);
                const header_content = try self.allocator.dupe(u8, self.out.items);
                const header_name = try std.fmt.allocPrint(self.allocator, "{s}.h", .{cname});
                try files.append(self.allocator, .{ .name = header_name, .content = header_content });

                // Generate impl
                self.out.clearRetainingCapacity();
                self.indent = 0;
                try self.emitClassImpl(s, class_names.items);
                const impl_content = try self.allocator.dupe(u8, self.out.items);
                const impl_name = try std.fmt.allocPrint(self.allocator, "{s}.cpp", .{cname});
                try files.append(self.allocator, .{ .name = impl_name, .content = impl_content });
            }
        }

        // Generate main.cpp with interfaces, free functions, and top-level statements
        self.out.clearRetainingCapacity();
        self.indent = 0;
        try self.emitMainFile(root, class_names.items);
        const main_content = try self.allocator.dupe(u8, self.out.items);
        try files.append(self.allocator, .{ .name = try self.allocator.dupe(u8, "main.cpp"), .content = main_content });

        return try self.allocator.dupe(OutputFile, files.items);
    }

    fn emitClassHeader(self: *CodeGenCpp, node: Node, class_names: []const []const u8) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        const ctor_node = self.tree.extra.items[es + 1 + field_count];
        const method_count = self.tree.extra.items[es + 2 + field_count];

        try self.w("#pragma once\n#include <cstdint>\n#include <cstdio>\n#include <cstdlib>\n#include <cstring>\n#include <cstdbool>\n\n");

        // Forward declarations / includes for other classes used in fields
        for (class_names) |cn| {
            if (!std.mem.eql(u8, cn, name)) {
                if (self.classUsedInFields(node, cn) or self.classUsedInMethods(node, cn)) {
                    try self.w("#include \""); try self.w(cn); try self.w(".h\"\n");
                }
            }
        }
        try self.w("\n");

        try self.w("class "); try self.w(name); try self.w(" {\npublic:\n");
        self.indent = 1;

        // Fields
        var fi: u32 = 0;
        while (fi < field_count) : (fi += 1) {
            const fnode = self.tree.nodes.items[self.tree.extra.items[es + 1 + fi]];
            try self.writeIndent();
            try self.w(self.typeStr(fnode.data.rhs));
            try self.w(" ");
            try self.w(self.tree.getString(unpackStringRef(fnode.data.lhs)));
            try self.w(";\n");
        }

        // Constructor declaration
        if (ctor_node != null_node) {
            const cnode = self.tree.nodes.items[ctor_node];
            const ces = cnode.data.lhs;
            const pc = self.tree.extra.items[ces];
            try self.writeIndent(); try self.w(name); try self.w("(");
            var pi: u32 = 0;
            while (pi < pc) : (pi += 1) {
                if (pi > 0) try self.w(", ");
                const pnode = self.tree.nodes.items[self.tree.extra.items[ces + 1 + pi]];
                try self.w(self.typeStr(pnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(pnode.data.lhs)));
            }
            try self.w(");\n");
        }

        // Method declarations
        var mi: u32 = 0;
        while (mi < method_count) : (mi += 1) {
            const mnode = self.tree.nodes.items[self.tree.extra.items[es + 3 + field_count + mi]];
            const mname = self.tree.getString(unpackStringRef(mnode.data.lhs));
            const mes = mnode.data.extra;
            const ret_node = self.tree.extra.items[mes];
            const mpc = self.tree.extra.items[mes + 1];
            try self.writeIndent();
            try self.w(if (ret_node != null_node) self.typeStr(ret_node) else "void");
            try self.w(" "); try self.w(mname); try self.w("(");
            var mpi: u32 = 0;
            while (mpi < mpc) : (mpi += 1) {
                if (mpi > 0) try self.w(", ");
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mpi]];
                try self.w(self.typeStr(mpnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(mpnode.data.lhs)));
            }
            try self.w(");\n");
        }

        self.indent = 0;
        try self.w("};\n");
    }

    fn emitClassImpl(self: *CodeGenCpp, node: Node, class_names: []const []const u8) !void {
        try self.emitClassImplBody(node, class_names, true);
    }

    fn emitClassImplBody(self: *CodeGenCpp, node: Node, class_names: []const []const u8, emit_includes: bool) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        const ctor_node = self.tree.extra.items[es + 1 + field_count];
        const method_count = self.tree.extra.items[es + 2 + field_count];

        if (emit_includes) {
            try self.w("#include \""); try self.w(name); try self.w(".h\"\n");
            for (class_names) |cn| {
                if (!std.mem.eql(u8, cn, name)) {
                    if (self.classUsedInMethods(node, cn)) {
                        try self.w("#include \""); try self.w(cn); try self.w(".h\"\n");
                    }
                }
            }
            try self.w("\n");
        }

        // Constructor implementation
        if (ctor_node != null_node) {
            const cnode = self.tree.nodes.items[ctor_node];
            const ces = cnode.data.lhs;
            const pc = self.tree.extra.items[ces];
            try self.w(name); try self.w("::"); try self.w(name); try self.w("(");
            var pi: u32 = 0;
            while (pi < pc) : (pi += 1) {
                if (pi > 0) try self.w(", ");
                const pnode = self.tree.nodes.items[self.tree.extra.items[ces + 1 + pi]];
                try self.w(self.typeStr(pnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(pnode.data.lhs)));
            }
            try self.w(") ");
            self.in_method = true;
            try self.emitBlock(cnode.data.rhs);
            self.in_method = false;
            try self.w("\n\n");
        }

        // Method implementations
        var mi: u32 = 0;
        while (mi < method_count) : (mi += 1) {
            const mnode = self.tree.nodes.items[self.tree.extra.items[es + 3 + field_count + mi]];
            const mname = self.tree.getString(unpackStringRef(mnode.data.lhs));
            const mes = mnode.data.extra;
            const ret_node = self.tree.extra.items[mes];
            const mpc = self.tree.extra.items[mes + 1];
            try self.w(if (ret_node != null_node) self.typeStr(ret_node) else "void");
            try self.w(" "); try self.w(name); try self.w("::"); try self.w(mname); try self.w("(");
            var mpi: u32 = 0;
            while (mpi < mpc) : (mpi += 1) {
                if (mpi > 0) try self.w(", ");
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mpi]];
                try self.w(self.typeStr(mpnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(mpnode.data.lhs)));
            }
            try self.w(") ");
            self.in_method = true;
            try self.emitBlock(mnode.data.rhs);
            self.in_method = false;
            try self.w("\n\n");
        }
    }

    fn emitMainFile(self: *CodeGenCpp, root: NodeIndex, class_names: []const []const u8) !void {
        const node = self.tree.nodes.items[root];
        const start_idx = node.data.lhs;
        const count = node.data.rhs;

        try self.w("#include <cstdint>\n#include <cstdio>\n#include <cstdlib>\n#include <cstring>\n#include <cstdbool>\n\n");

        // Include all class headers
        for (class_names) |cn| {
            try self.w("#include \""); try self.w(cn); try self.w(".h\"\n");
        }
        try self.w("\n");

        // Interfaces as structs
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag == .interface_decl) try self.emitInterfaceDecl(s);
        }

        // Forward declarations for free functions
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag == .func_decl) try self.emitFuncSig(s, true);
        }
        try self.w("\n");

        // Free function bodies
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag == .func_decl) { try self.emitFuncSig(s, false); try self.w(" "); try self.emitBlock(s.data.rhs); try self.w("\n\n"); }
        }

        // main()
        var has_top = false;
        i = 0;
        while (i < count) : (i += 1) { const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]]; if (s.tag != .func_decl and s.tag != .interface_decl and s.tag != .class_decl and s.tag != .import_decl) { has_top = true; break; } }
        if (has_top) {
            try self.w("int main() {\n"); self.indent += 1;
            i = 0;
            while (i < count) : (i += 1) { const idx = self.tree.extra.items[start_idx + i]; const s = self.tree.nodes.items[idx]; if (s.tag != .func_decl and s.tag != .interface_decl and s.tag != .class_decl and s.tag != .import_decl) try self.emitStmt(idx); }
            try self.writeIndent(); try self.w("return 0;\n"); self.indent -= 1; try self.w("}\n");
        }
    }

    // Simple heuristic: check if a class name appears in field types
    fn classUsedInFields(self: *CodeGenCpp, node: Node, class_name: []const u8) bool {
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        var fi: u32 = 0;
        while (fi < field_count) : (fi += 1) {
            const fnode = self.tree.nodes.items[self.tree.extra.items[es + 1 + fi]];
            if (fnode.data.rhs != null_node) {
                const tnode = self.tree.nodes.items[fnode.data.rhs];
                if (tnode.tag == .type_name) {
                    if (std.mem.eql(u8, self.tree.getString(unpackStringRef(tnode.data.lhs)), class_name)) return true;
                }
            }
        }
        return false;
    }

    fn classUsedInMethods(self: *CodeGenCpp, node: Node, class_name: []const u8) bool {
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        const method_count = self.tree.extra.items[es + 2 + field_count];
        var mi: u32 = 0;
        while (mi < method_count) : (mi += 1) {
            const mnode = self.tree.nodes.items[self.tree.extra.items[es + 3 + field_count + mi]];
            const mes = mnode.data.extra;
            const ret_node = self.tree.extra.items[mes];
            if (ret_node != null_node) {
                const tnode = self.tree.nodes.items[ret_node];
                if (tnode.tag == .type_name and std.mem.eql(u8, self.tree.getString(unpackStringRef(tnode.data.lhs)), class_name)) return true;
            }
            const mpc = self.tree.extra.items[mes + 1];
            var mpi: u32 = 0;
            while (mpi < mpc) : (mpi += 1) {
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mpi]];
                if (mpnode.data.rhs != null_node) {
                    const tnode = self.tree.nodes.items[mpnode.data.rhs];
                    if (tnode.tag == .type_name and std.mem.eql(u8, self.tree.getString(unpackStringRef(tnode.data.lhs)), class_name)) return true;
                }
            }
        }
        return false;
    }

    fn emitInterfaceDecl(self: *CodeGenCpp, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.rhs;
        const fc = self.tree.extra.items[es];
        try self.w("struct "); try self.w(name); try self.w(" {\n"); self.indent += 1;
        var fi: u32 = 0;
        while (fi < fc) : (fi += 1) { const f = self.tree.nodes.items[self.tree.extra.items[es + 1 + fi]]; try self.writeIndent(); try self.w(self.typeStr(f.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(f.data.lhs))); try self.w(";\n"); }
        self.indent -= 1; try self.w("};\n\n");
    }

    fn emitFuncSig(self: *CodeGenCpp, node: Node, fwd: bool) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const ret_node = self.tree.extra.items[es];
        const pc = self.tree.extra.items[es + 1];
        try self.w(if (ret_node != null_node) self.typeStr(ret_node) else "void");
        try self.w(" "); try self.w(name); try self.w("(");
        var pi: u32 = 0;
        while (pi < pc) : (pi += 1) {
            if (pi > 0) try self.w(", ");
            const p = self.tree.nodes.items[self.tree.extra.items[es + 2 + pi]];
            try self.w(self.typeStr(p.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(p.data.lhs)));
        }
        if (fwd) try self.w(");\n") else try self.w(")");
    }

    fn emitStmt(self: *CodeGenCpp, idx: NodeIndex) anyerror!void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        switch (node.tag) {
            .var_decl => try self.emitVarDecl(node),
            .if_stmt => try self.emitIfStmt(node),
            .while_stmt => { try self.writeIndent(); try self.w("while ("); try self.emitExpr(node.data.lhs); try self.w(") "); try self.emitBlock(node.data.rhs); try self.w("\n"); },
            .for_stmt => try self.emitForStmt(node),
            .return_stmt => { try self.writeIndent(); if (node.data.lhs != null_node) { try self.w("return "); try self.emitExpr(node.data.lhs); try self.w(";\n"); } else try self.w("return;\n"); },
            .expr_stmt => { if (try self.tryEmitConsoleLog(node.data.lhs)) return; try self.writeIndent(); try self.emitExpr(node.data.lhs); try self.w(";\n"); },
            .block => try self.emitBlock(idx),
            else => {},
        }
    }

    fn emitVarDecl(self: *CodeGenCpp, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const type_node = self.tree.extra.items[es];
        const is_const = self.tree.extra.items[es + 1] != 0;

        // Bridge mode: translate `const c = new Counter(0)` → `Counter* c = counter_create(0)`
        if (self.bridge_mode and node.data.rhs != null_node) {
            const rhs_node = self.tree.nodes.items[node.data.rhs];
            if (rhs_node.tag == .new_expr) {
                const cname = self.tree.getString(unpackStringRef(rhs_node.data.lhs));
                const lower = try self.lowerName(cname);
                defer self.allocator.free(lower);
                try self.class_vars.append(self.allocator, .{ .name = name, .class_name = cname });
                try self.writeIndent();
                try self.w(cname); try self.w("* "); try self.w(name); try self.w(" = ");
                try self.w(lower); try self.w("_create(");
                const aes = rhs_node.data.rhs;
                const ac = self.tree.extra.items[aes];
                var ai: u32 = 0;
                while (ai < ac) : (ai += 1) { if (ai > 0) try self.w(", "); try self.emitExpr(self.tree.extra.items[aes + 1 + ai]); }
                try self.w(");\n");
                return;
            }
        }

        try self.writeIndent();
        const type_s = if (type_node != null_node) self.typeStr(type_node) else if (self.bridge_mode) "double" else "auto";
        if (is_const and !std.mem.startsWith(u8, type_s, "const ")) try self.w("const ");
        try self.w(type_s);
        try self.w(" "); try self.w(name);
        if (node.data.rhs != null_node) { try self.w(" = "); try self.emitExpr(node.data.rhs); }
        try self.w(";\n");
    }

    fn emitIfStmt(self: *CodeGenCpp, node: Node) !void {
        try self.writeIndent(); try self.w("if ("); try self.emitExpr(node.data.lhs); try self.w(") ");
        try self.emitBlock(node.data.rhs);
        const else_node = self.tree.extra.items[node.data.extra];
        if (else_node != null_node) {
            const en = self.tree.nodes.items[else_node];
            if (en.tag == .if_stmt) { try self.w(" else "); try self.emitIfStmt(en); } else { try self.w(" else "); try self.emitBlock(else_node); try self.w("\n"); }
        } else try self.w("\n");
    }

    fn emitForStmt(self: *CodeGenCpp, node: Node) !void {
        const es = node.data.lhs;
        const init_n = self.tree.extra.items[es]; const cond_n = self.tree.extra.items[es + 1]; const upd_n = self.tree.extra.items[es + 2];
        try self.writeIndent(); try self.w("for (");
        if (init_n != null_node) { const inode = self.tree.nodes.items[init_n]; if (inode.tag == .var_decl) try self.emitVarDeclInline(inode) else try self.emitExpr(init_n); }
        try self.w("; ");
        if (cond_n != null_node) try self.emitExpr(cond_n);
        try self.w("; ");
        if (upd_n != null_node) try self.emitExpr(upd_n);
        try self.w(") "); try self.emitBlock(node.data.rhs); try self.w("\n");
    }

    fn emitVarDeclInline(self: *CodeGenCpp, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const tn = self.tree.extra.items[node.data.extra];
        try self.w(if (tn != null_node) self.typeStr(tn) else "auto");
        try self.w(" "); try self.w(name);
        if (node.data.rhs != null_node) { try self.w(" = "); try self.emitExpr(node.data.rhs); }
    }

    fn emitBlock(self: *CodeGenCpp, idx: NodeIndex) anyerror!void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        if (node.tag != .block) { try self.emitStmt(idx); return; }
        try self.w("{\n"); self.indent += 1;
        var i: u32 = 0; while (i < node.data.rhs) : (i += 1) try self.emitStmt(self.tree.extra.items[node.data.lhs + i]);
        self.indent -= 1; try self.writeIndent(); try self.w("}");
    }

    fn emitExpr(self: *CodeGenCpp, idx: NodeIndex) !void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        switch (node.tag) {
            .number_lit, .string_lit, .identifier => try self.w(self.tree.getString(unpackStringRef(node.data.lhs))),
            .bool_lit => try self.w(if (node.data.lhs != 0) "true" else "false"),
            .this_expr => try self.w("this"),
            .new_expr => {
                const cname = self.tree.getString(unpackStringRef(node.data.lhs));
                if (self.bridge_mode) {
                    const lower = try self.lowerName(cname);
                    defer self.allocator.free(lower);
                    try self.w(lower); try self.w("_create(");
                } else {
                    try self.w("new "); try self.w(cname); try self.w("(");
                }
                const aes = node.data.rhs; const ac = self.tree.extra.items[aes];
                var ai: u32 = 0;
                while (ai < ac) : (ai += 1) { if (ai > 0) try self.w(", "); try self.emitExpr(self.tree.extra.items[aes + 1 + ai]); }
                try self.w(")");
            },
            .binary_expr => { const op: Op = @enumFromInt(self.tree.extra.items[node.data.extra]); try self.w("("); try self.emitExpr(node.data.lhs); try self.w(opStr(op)); try self.emitExpr(node.data.rhs); try self.w(")"); },
            .unary_expr => { const op: Op = @enumFromInt(node.data.rhs); try self.w(if (op == .logical_not) "!" else "-"); try self.emitExpr(node.data.lhs); },
            .assign_expr => { try self.emitExpr(node.data.lhs); const op: Op = @enumFromInt(self.tree.extra.items[node.data.extra]); try self.w(assignStr(op)); try self.emitExpr(node.data.rhs); },
            .call_expr => {
                // Bridge mode: translate obj.method(args) → classname_method(obj, args)
                if (self.bridge_mode) {
                    const callee = self.tree.nodes.items[node.data.lhs];
                    if (callee.tag == .member_expr) {
                        const obj_node = self.tree.nodes.items[callee.data.lhs];
                        if (obj_node.tag == .identifier) {
                            const obj_name = self.tree.getString(unpackStringRef(obj_node.data.lhs));
                            if (self.lookupClassVar(obj_name)) |cn| {
                                const lower = try self.lowerName(cn);
                                defer self.allocator.free(lower);
                                const method = self.tree.getString(unpackStringRef(callee.data.rhs));
                                try self.w(lower); try self.w("_"); try self.w(method); try self.w("(");
                                try self.w(obj_name);
                                const aes = node.data.rhs; const ac = self.tree.extra.items[aes];
                                var ai: u32 = 0;
                                while (ai < ac) : (ai += 1) { try self.w(", "); try self.emitExpr(self.tree.extra.items[aes + 1 + ai]); }
                                try self.w(")");
                                return;
                            }
                        }
                    }
                }
                try self.emitExpr(node.data.lhs); try self.w("("); const aes = node.data.rhs; const ac = self.tree.extra.items[aes]; var ai: u32 = 0; while (ai < ac) : (ai += 1) { if (ai > 0) try self.w(", "); try self.emitExpr(self.tree.extra.items[aes + 1 + ai]); } try self.w(")");
            },
            .member_expr => {
                try self.emitExpr(node.data.lhs);
                // Use -> for this pointer, . for everything else
                const lhs_node = self.tree.nodes.items[node.data.lhs];
                if (lhs_node.tag == .this_expr) try self.w("->") else try self.w(".");
                try self.w(self.tree.getString(unpackStringRef(node.data.rhs)));
            },
            .index_expr => { try self.emitExpr(node.data.lhs); try self.w("["); try self.emitExpr(node.data.rhs); try self.w("]"); },
            .array_lit => { try self.w("{ "); var ei: u32 = 0; while (ei < node.data.rhs) : (ei += 1) { if (ei > 0) try self.w(", "); try self.emitExpr(self.tree.extra.items[node.data.lhs + ei]); } try self.w(" }"); },
            .object_lit => { try self.w("{ "); var oi: u32 = 0; while (oi < node.data.rhs) : (oi += 1) { if (oi > 0) try self.w(", "); try self.w("."); try self.w(self.tree.getString(unpackStringRef(self.tree.extra.items[node.data.lhs + oi * 2]))); try self.w(" = "); try self.emitExpr(self.tree.extra.items[node.data.lhs + oi * 2 + 1]); } try self.w(" }"); },
            else => try self.w("/* unsupported */"),
        }
    }

    fn tryEmitConsoleLog(self: *CodeGenCpp, idx: NodeIndex) !bool {
        if (idx == null_node) return false;
        const node = self.tree.nodes.items[idx];
        if (node.tag != .call_expr) return false;
        const callee = self.tree.nodes.items[node.data.lhs];
        if (callee.tag != .member_expr) return false;
        const obj = self.tree.nodes.items[callee.data.lhs];
        if (obj.tag != .identifier) return false;
        if (!std.mem.eql(u8, self.tree.getString(unpackStringRef(obj.data.lhs)), "console")) return false;
        if (!std.mem.eql(u8, self.tree.getString(unpackStringRef(callee.data.rhs)), "log")) return false;
        const aes = node.data.rhs;
        const ac = self.tree.extra.items[aes];
        try self.writeIndent(); try self.w("printf(\"");
        var ai: u32 = 0;
        while (ai < ac) : (ai += 1) { if (ai > 0) try self.w(" "); try self.w(self.inferFmt(self.tree.extra.items[aes + 1 + ai])); }
        try self.w("\\n\"");
        ai = 0; while (ai < ac) : (ai += 1) { try self.w(", "); try self.emitExpr(self.tree.extra.items[aes + 1 + ai]); }
        try self.w(");\n");
        return true;
    }

    fn inferFmt(self: *CodeGenCpp, idx: NodeIndex) []const u8 {
        if (idx == null_node) return "%g";
        const node = self.tree.nodes.items[idx];
        return switch (node.tag) {
            .number_lit => "%g", .string_lit => "%s", .bool_lit => "%d",
            .identifier => blk: {
                const name = self.tree.getString(unpackStringRef(node.data.lhs));
                if (self.checker.lookupSymbol(name)) |sym| break :blk switch (sym.type_info.base) {
                    .number, .f64_t, .f32_t => "%g", .i32_t, .i64_t => "%d", .string => "%s", .boolean => "%d", else => "%g",
                };
                break :blk "%g";
            },
            .call_expr => blk: {
                // Check return type of method calls on class instances
                const callee = self.tree.nodes.items[node.data.lhs];
                if (callee.tag == .member_expr) {
                    const method = self.tree.getString(unpackStringRef(callee.data.rhs));
                    const obj = self.tree.nodes.items[callee.data.lhs];
                    if (obj.tag == .identifier) {
                        const obj_name = self.tree.getString(unpackStringRef(obj.data.lhs));
                        if (self.checker.lookupSymbol(obj_name)) |sym| {
                            if (sym.type_info.base == .class_t and sym.type_info.detail < self.checker.classes.items.len) {
                                const cd = self.checker.classes.items[sym.type_info.detail];
                                for (cd.methods) |m| {
                                    if (std.mem.eql(u8, m.name, method)) break :blk switch (m.return_type.base) {
                                        .number, .f64_t, .f32_t => "%g", .i32_t, .i64_t => "%d", .string => "%s", .boolean => "%d", else => "%g",
                                    };
                                }
                            }
                        }
                    }
                }
                break :blk "%g";
            },
            else => "%g",
        };
    }

    fn typeStr(self: *CodeGenCpp, idx: NodeIndex) []const u8 {
        if (idx == null_node) return "double";
        const node = self.tree.nodes.items[idx];
        if (node.tag == .type_name) {
            const name = self.tree.getString(unpackStringRef(node.data.lhs));
            if (std.mem.eql(u8, name, "number")) return "double";
            if (std.mem.eql(u8, name, "boolean")) return "bool";
            if (std.mem.eql(u8, name, "string")) return "const char*";
            if (std.mem.eql(u8, name, "void")) return "void";
            if (std.mem.eql(u8, name, "i32")) return "int32_t";
            if (std.mem.eql(u8, name, "i64")) return "int64_t";
            if (std.mem.eql(u8, name, "f32")) return "float";
            if (std.mem.eql(u8, name, "f64")) return "double";
            // Class types → ClassName* (pointer)
            for (self.checker.classes.items) |c| if (std.mem.eql(u8, c.name, name)) return name;
            return name;
        }
        if (node.tag == .type_array) return "double*";
        return "double";
    }

    // ── Unified output: <base>.h + <base>.cpp + <base>.c ────────────────

    pub fn generateUnified(self: *CodeGenCpp, root: NodeIndex, basename: []const u8) ![]OutputFile {
        const node = self.tree.nodes.items[root];
        if (node.tag != .program) return &[_]OutputFile{};

        var files: std.ArrayList(OutputFile) = .empty;
        defer files.deinit(self.allocator);

        // Collect class names
        const start = node.data.lhs;
        const count = node.data.rhs;
        var class_names: std.ArrayList([]const u8) = .empty;
        defer class_names.deinit(self.allocator);
        var ci: u32 = 0;
        while (ci < count) : (ci += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start + ci]];
            if (s.tag == .class_decl) try class_names.append(self.allocator, self.tree.getString(unpackStringRef(s.data.lhs)));
        }

        // 1. Unified header
        self.out.clearRetainingCapacity();
        self.indent = 0;
        try self.emitUnifiedHeader(root, basename, class_names.items);
        const h_content = try self.allocator.dupe(u8, self.out.items);
        try files.append(self.allocator, .{
            .name = try std.fmt.allocPrint(self.allocator, "{s}.h", .{basename}),
            .content = h_content,
        });

        // 2. C++ implementation + bridge
        self.out.clearRetainingCapacity();
        self.indent = 0;
        try self.emitUnifiedCppImpl(root, basename, class_names.items);
        const cpp_content = try self.allocator.dupe(u8, self.out.items);
        try files.append(self.allocator, .{
            .name = try std.fmt.allocPrint(self.allocator, "{s}.cpp", .{basename}),
            .content = cpp_content,
        });

        // 3. C entrypoint
        self.out.clearRetainingCapacity();
        self.indent = 0;
        self.bridge_mode = true;
        self.class_vars.clearRetainingCapacity();
        try self.emitUnifiedCEntry(root, basename);
        self.bridge_mode = false;
        const c_content = try self.allocator.dupe(u8, self.out.items);
        try files.append(self.allocator, .{
            .name = try std.fmt.allocPrint(self.allocator, "{s}.c", .{basename}),
            .content = c_content,
        });

        return try self.allocator.dupe(OutputFile, files.items);
    }

    fn emitUnifiedHeader(self: *CodeGenCpp, root: NodeIndex, basename: []const u8, class_names: []const []const u8) !void {
        _ = basename;
        const node = self.tree.nodes.items[root];
        const start_idx = node.data.lhs;
        const count = node.data.rhs;

        try self.w("#pragma once\n\n#ifdef __cplusplus\n#include <cstdint>\n#include <cstdio>\n#else\n#include <stdint.h>\n#include <stdio.h>\n#include <stdbool.h>\n#endif\n\n");

        // Interfaces as C-compatible typedef structs
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag == .interface_decl) {
                const name = self.tree.getString(unpackStringRef(s.data.lhs));
                const es = s.data.rhs;
                const fc = self.tree.extra.items[es];
                try self.w("typedef struct {\n");
                var fi: u32 = 0;
                while (fi < fc) : (fi += 1) {
                    const f = self.tree.nodes.items[self.tree.extra.items[es + 1 + fi]];
                    try self.w("    "); try self.w(self.typeStr(f.data.rhs)); try self.w(" ");
                    try self.w(self.tree.getString(unpackStringRef(f.data.lhs))); try self.w(";\n");
                }
                try self.w("} "); try self.w(name); try self.w(";\n\n");
            }
        }

        // C++ class declarations
        if (class_names.len > 0) {
            try self.w("#ifdef __cplusplus\n");
            i = 0;
            while (i < count) : (i += 1) {
                const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
                if (s.tag == .class_decl) try self.emitClassHeaderBody(s);
            }
            try self.w("extern \"C\" {\n#else\n");
            // C opaque typedefs
            for (class_names) |cn| {
                try self.w("typedef struct "); try self.w(cn); try self.w(" "); try self.w(cn); try self.w(";\n");
            }
            try self.w("#endif\n\n");

            // Bridge declarations (visible to both C and C++)
            i = 0;
            while (i < count) : (i += 1) {
                const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
                if (s.tag == .class_decl) try self.emitBridgeDecls(s);
            }
            try self.w("\n#ifdef __cplusplus\n}\n#endif\n");
        }
    }

    /// Emit class body for the unified header (fields + method declarations).
    fn emitClassHeaderBody(self: *CodeGenCpp, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        const ctor_node = self.tree.extra.items[es + 1 + field_count];
        const method_count = self.tree.extra.items[es + 2 + field_count];

        try self.w("class "); try self.w(name); try self.w(" {\npublic:\n");
        // Fields
        var fi: u32 = 0;
        while (fi < field_count) : (fi += 1) {
            const fnode = self.tree.nodes.items[self.tree.extra.items[es + 1 + fi]];
            try self.w("    "); try self.w(self.typeStr(fnode.data.rhs)); try self.w(" ");
            try self.w(self.tree.getString(unpackStringRef(fnode.data.lhs))); try self.w(";\n");
        }
        // Constructor
        if (ctor_node != null_node) {
            const cnode = self.tree.nodes.items[ctor_node];
            const ces = cnode.data.lhs;
            const pc = self.tree.extra.items[ces];
            try self.w("    "); try self.w(name); try self.w("(");
            var pi: u32 = 0;
            while (pi < pc) : (pi += 1) {
                if (pi > 0) try self.w(", ");
                const pnode = self.tree.nodes.items[self.tree.extra.items[ces + 1 + pi]];
                try self.w(self.typeStr(pnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(pnode.data.lhs)));
            }
            try self.w(");\n");
        }
        // Methods
        var mi: u32 = 0;
        while (mi < method_count) : (mi += 1) {
            const mnode = self.tree.nodes.items[self.tree.extra.items[es + 3 + field_count + mi]];
            const mname = self.tree.getString(unpackStringRef(mnode.data.lhs));
            const mes = mnode.data.extra;
            const ret_node = self.tree.extra.items[mes];
            const mpc = self.tree.extra.items[mes + 1];
            try self.w("    "); try self.w(if (ret_node != null_node) self.typeStr(ret_node) else "void");
            try self.w(" "); try self.w(mname); try self.w("(");
            var mpi: u32 = 0;
            while (mpi < mpc) : (mpi += 1) {
                if (mpi > 0) try self.w(", ");
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mpi]];
                try self.w(self.typeStr(mpnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(mpnode.data.lhs)));
            }
            try self.w(");\n");
        }
        try self.w("};\n\n");
    }

    /// Emit extern "C" bridge declarations for a class.
    fn emitBridgeDecls(self: *CodeGenCpp, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const lower = try self.lowerName(name);
        defer self.allocator.free(lower);
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        const ctor_node = self.tree.extra.items[es + 1 + field_count];
        const method_count = self.tree.extra.items[es + 2 + field_count];

        // Constructor bridge
        if (ctor_node != null_node) {
            const cnode = self.tree.nodes.items[ctor_node];
            const ces = cnode.data.lhs;
            const pc = self.tree.extra.items[ces];
            try self.w(name); try self.w("* "); try self.w(lower); try self.w("_create(");
            var pi: u32 = 0;
            while (pi < pc) : (pi += 1) {
                if (pi > 0) try self.w(", ");
                const pnode = self.tree.nodes.items[self.tree.extra.items[ces + 1 + pi]];
                try self.w(self.typeStr(pnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(pnode.data.lhs)));
            }
            try self.w(");\n");
        }
        // Method bridges
        var mi: u32 = 0;
        while (mi < method_count) : (mi += 1) {
            const mnode = self.tree.nodes.items[self.tree.extra.items[es + 3 + field_count + mi]];
            const mname = self.tree.getString(unpackStringRef(mnode.data.lhs));
            const mes = mnode.data.extra;
            const ret_node = self.tree.extra.items[mes];
            const mpc = self.tree.extra.items[mes + 1];
            try self.w(if (ret_node != null_node) self.typeStr(ret_node) else "void");
            try self.w(" "); try self.w(lower); try self.w("_"); try self.w(mname); try self.w("(");
            try self.w(name); try self.w("* self");
            var mpi: u32 = 0;
            while (mpi < mpc) : (mpi += 1) {
                try self.w(", ");
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mpi]];
                try self.w(self.typeStr(mpnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(mpnode.data.lhs)));
            }
            try self.w(");\n");
        }
        // Destroy bridge
        try self.w("void "); try self.w(lower); try self.w("_destroy("); try self.w(name); try self.w("* self);\n");
    }

    fn emitUnifiedCppImpl(self: *CodeGenCpp, root: NodeIndex, basename: []const u8, class_names: []const []const u8) !void {
        const node = self.tree.nodes.items[root];
        const start_idx = node.data.lhs;
        const count = node.data.rhs;

        try self.w("#include \""); try self.w(basename); try self.w(".h\"\n\n");

        // Class implementations (no per-class includes — unified header handles it)
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const idx = self.tree.extra.items[start_idx + i];
            const s = self.tree.nodes.items[idx];
            if (s.tag == .class_decl) {
                try self.emitClassImplBody(s, class_names, false);
            }
        }

        // Bridge implementations
        try self.w("extern \"C\" {\n\n");
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag == .class_decl) try self.emitBridgeImpls(s);
        }
        try self.w("}\n");
    }

    /// Emit extern "C" bridge function implementations for a class.
    fn emitBridgeImpls(self: *CodeGenCpp, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const lower = try self.lowerName(name);
        defer self.allocator.free(lower);
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        const ctor_node = self.tree.extra.items[es + 1 + field_count];
        const method_count = self.tree.extra.items[es + 2 + field_count];

        // Create
        if (ctor_node != null_node) {
            const cnode = self.tree.nodes.items[ctor_node];
            const ces = cnode.data.lhs;
            const pc = self.tree.extra.items[ces];
            try self.w(name); try self.w("* "); try self.w(lower); try self.w("_create(");
            var pi: u32 = 0;
            while (pi < pc) : (pi += 1) {
                if (pi > 0) try self.w(", ");
                const pnode = self.tree.nodes.items[self.tree.extra.items[ces + 1 + pi]];
                try self.w(self.typeStr(pnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(pnode.data.lhs)));
            }
            try self.w(") { return new "); try self.w(name); try self.w("(");
            pi = 0;
            while (pi < pc) : (pi += 1) {
                if (pi > 0) try self.w(", ");
                const pnode = self.tree.nodes.items[self.tree.extra.items[ces + 1 + pi]];
                try self.w(self.tree.getString(unpackStringRef(pnode.data.lhs)));
            }
            try self.w("); }\n");
        }
        // Methods
        var mi: u32 = 0;
        while (mi < method_count) : (mi += 1) {
            const mnode = self.tree.nodes.items[self.tree.extra.items[es + 3 + field_count + mi]];
            const mname = self.tree.getString(unpackStringRef(mnode.data.lhs));
            const mes = mnode.data.extra;
            const ret_node = self.tree.extra.items[mes];
            const mpc = self.tree.extra.items[mes + 1];
            const ret_type = if (ret_node != null_node) self.typeStr(ret_node) else "void";
            const has_return = ret_node != null_node and !std.mem.eql(u8, ret_type, "void");
            try self.w(ret_type);
            try self.w(" "); try self.w(lower); try self.w("_"); try self.w(mname); try self.w("(");
            try self.w(name); try self.w("* self");
            var mpi: u32 = 0;
            while (mpi < mpc) : (mpi += 1) {
                try self.w(", ");
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mpi]];
                try self.w(self.typeStr(mpnode.data.rhs)); try self.w(" "); try self.w(self.tree.getString(unpackStringRef(mpnode.data.lhs)));
            }
            try self.w(") { ");
            if (has_return) try self.w("return ");
            try self.w("self->"); try self.w(mname); try self.w("(");
            mpi = 0;
            while (mpi < mpc) : (mpi += 1) {
                if (mpi > 0) try self.w(", ");
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mpi]];
                try self.w(self.tree.getString(unpackStringRef(mpnode.data.lhs)));
            }
            try self.w("); }\n");
        }
        // Destroy
        try self.w("void "); try self.w(lower); try self.w("_destroy("); try self.w(name); try self.w("* self) { delete self; }\n\n");
    }

    fn emitUnifiedCEntry(self: *CodeGenCpp, root: NodeIndex, basename: []const u8) !void {
        const node = self.tree.nodes.items[root];
        const start_idx = node.data.lhs;
        const count = node.data.rhs;

        try self.w("#include \""); try self.w(basename); try self.w(".h\"\n\n");

        // Free functions
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag == .func_decl) try self.emitFuncSig(s, true);
        }
        var has_funcs = false;
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag == .func_decl) { has_funcs = true; try self.emitFuncSig(s, false); try self.w(" "); try self.emitBlock(s.data.rhs); try self.w("\n\n"); }
        }
        if (has_funcs) try self.w("\n");

        // main()
        var has_top = false;
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start_idx + i]];
            if (s.tag != .func_decl and s.tag != .interface_decl and s.tag != .class_decl and s.tag != .import_decl) { has_top = true; break; }
        }
        if (has_top) {
            try self.w("int main(void) {\n"); self.indent += 1;
            i = 0;
            while (i < count) : (i += 1) {
                const idx = self.tree.extra.items[start_idx + i];
                const s = self.tree.nodes.items[idx];
                if (s.tag != .func_decl and s.tag != .interface_decl and s.tag != .class_decl and s.tag != .import_decl)
                    try self.emitStmt(idx);
            }
            try self.writeIndent(); try self.w("return 0;\n"); self.indent -= 1; try self.w("}\n");
        }
    }

    fn lowerName(self: *CodeGenCpp, name: []const u8) ![]u8 {
        const lower = try self.allocator.dupe(u8, name);
        for (lower) |*ch| ch.* = std.ascii.toLower(ch.*);
        return lower;
    }

    fn lookupClassVar(self: *CodeGenCpp, name: []const u8) ?[]const u8 {
        for (self.class_vars.items) |cv| {
            if (std.mem.eql(u8, cv.name, name)) return cv.class_name;
        }
        return null;
    }

    fn w(self: *CodeGenCpp, s: []const u8) !void { try self.out.appendSlice(self.allocator, s); }
    fn writeIndent(self: *CodeGenCpp) !void { var i: u32 = 0; while (i < self.indent) : (i += 1) try self.out.appendSlice(self.allocator, "    "); }

    fn opStr(op: Op) []const u8 {
        return switch (op) { .add => " + ", .sub => " - ", .mul => " * ", .div => " / ", .mod => " % ", .eq, .strict_eq => " == ", .neq, .strict_neq => " != ", .lt => " < ", .gt => " > ", .lte => " <= ", .gte => " >= ", .logical_and => " && ", .logical_or => " || ", else => " ? " };
    }
    fn assignStr(op: Op) []const u8 {
        return switch (op) { .assign => " = ", .add_assign => " += ", .sub_assign => " -= ", .mul_assign => " *= ", .div_assign => " /= ", else => " = " };
    }
};
