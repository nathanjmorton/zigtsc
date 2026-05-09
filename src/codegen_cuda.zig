const std = @import("std");
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;
const NodeIndex = ast_mod.NodeIndex;
const null_node = ast_mod.null_node;
const Op = ast_mod.Op;
const unpackStringRef = ast_mod.unpackStringRef;
const Checker = @import("checker.zig").Checker;

pub const CodeGenCuda = struct {
    tree: *const ast_mod.Ast,
    checker: *const Checker,
    out: std.ArrayList(u8) = .empty,
    indent: u32 = 0,
    allocator: std.mem.Allocator,

    pub fn init(tree: *const ast_mod.Ast, checker: *const Checker, allocator: std.mem.Allocator) CodeGenCuda {
        return .{ .tree = tree, .checker = checker, .allocator = allocator };
    }

    pub fn deinit(self: *CodeGenCuda) void { self.out.deinit(self.allocator); }

    pub fn generate(self: *CodeGenCuda, root: NodeIndex) ![]const u8 {
        const node = self.tree.nodes.items[root];
        if (node.tag != .program) return "";
        const start = node.data.lhs;
        const count = node.data.rhs;

        try self.w("#include <cuda_runtime.h>\n#include <stdio.h>\n#include <stdlib.h>\n#include <stdint.h>\n#include <stdbool.h>\n\n");

        // Interfaces as structs
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start + i]];
            if (s.tag == .interface_decl) try self.emitInterfaceDecl(s);
        }

        // Forward declarations for host functions
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start + i]];
            if (s.tag == .func_decl) try self.emitFuncSig(s, null, true);
        }
        try self.w("\n");

        // Kernel functions (__global__)
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start + i]];
            if (s.tag == .kernel_decl) {
                try self.emitFuncSig(s, "__global__", false);
                try self.w(" ");
                try self.emitBlock(s.data.rhs);
                try self.w("\n\n");
            }
        }

        // Host function bodies
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start + i]];
            if (s.tag == .func_decl) {
                try self.emitFuncSig(s, null, false);
                try self.w(" ");
                try self.emitBlock(s.data.rhs);
                try self.w("\n\n");
            }
        }

        // main()
        var has_top = false;
        i = 0;
        while (i < count) : (i += 1) {
            const s = self.tree.nodes.items[self.tree.extra.items[start + i]];
            if (s.tag != .func_decl and s.tag != .kernel_decl and s.tag != .interface_decl and s.tag != .import_decl) {
                has_top = true;
                break;
            }
        }
        if (has_top) {
            try self.w("int main(void) {\n");
            self.indent += 1;
            i = 0;
            while (i < count) : (i += 1) {
                const idx = self.tree.extra.items[start + i];
                const s = self.tree.nodes.items[idx];
                if (s.tag != .func_decl and s.tag != .kernel_decl and s.tag != .interface_decl and s.tag != .import_decl)
                    try self.emitStmt(idx);
            }
            try self.writeIndent();
            try self.w("return 0;\n");
            self.indent -= 1;
            try self.w("}\n");
        }

        return self.out.items;
    }

    fn emitInterfaceDecl(self: *CodeGenCuda, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.rhs;
        const fc = self.tree.extra.items[es];
        try self.w("typedef struct {\n");
        self.indent += 1;
        var i: u32 = 0;
        while (i < fc) : (i += 1) {
            const f = self.tree.nodes.items[self.tree.extra.items[es + 1 + i]];
            try self.writeIndent();
            try self.w(self.typeStr(f.data.rhs));
            try self.w(" ");
            try self.w(self.tree.getString(unpackStringRef(f.data.lhs)));
            try self.w(";\n");
        }
        self.indent -= 1;
        try self.w("} ");
        try self.w(name);
        try self.w(";\n\n");
    }

    fn emitFuncSig(self: *CodeGenCuda, node: Node, qualifier: ?[]const u8, fwd: bool) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const ret_node = self.tree.extra.items[es];
        const pc = self.tree.extra.items[es + 1];
        if (qualifier) |q| {
            try self.w(q);
            try self.w(" ");
        }
        try self.w(if (ret_node != null_node) self.typeStr(ret_node) else "void");
        try self.w(" ");
        try self.w(name);
        try self.w("(");
        var pi: u32 = 0;
        while (pi < pc) : (pi += 1) {
            if (pi > 0) try self.w(", ");
            const p = self.tree.nodes.items[self.tree.extra.items[es + 2 + pi]];
            try self.w(self.typeStr(p.data.rhs));
            try self.w(" ");
            try self.w(self.tree.getString(unpackStringRef(p.data.lhs)));
        }
        if (pc == 0 and qualifier == null) try self.w("void");
        if (fwd) try self.w(");\n") else try self.w(")");
    }

    fn emitStmt(self: *CodeGenCuda, idx: NodeIndex) anyerror!void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        switch (node.tag) {
            .var_decl => try self.emitVarDecl(node),
            .if_stmt => try self.emitIfStmt(node),
            .while_stmt => {
                try self.writeIndent();
                try self.w("while (");
                try self.emitExpr(node.data.lhs);
                try self.w(") ");
                try self.emitBlock(node.data.rhs);
                try self.w("\n");
            },
            .for_stmt => try self.emitForStmt(node),
            .return_stmt => {
                try self.writeIndent();
                if (node.data.lhs != null_node) {
                    try self.w("return ");
                    try self.emitExpr(node.data.lhs);
                    try self.w(";\n");
                } else try self.w("return;\n");
            },
            .expr_stmt => {
                if (try self.tryEmitConsoleLog(node.data.lhs)) return;
                try self.writeIndent();
                try self.emitExpr(node.data.lhs);
                try self.w(";\n");
            },
            .block => try self.emitBlock(idx),
            else => {},
        }
    }

    fn emitVarDecl(self: *CodeGenCuda, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const type_node = self.tree.extra.items[es];
        const is_const = self.tree.extra.items[es + 1] != 0;
        try self.writeIndent();
        const type_s = if (type_node != null_node) self.typeStr(type_node) else "double";
        if (is_const and !std.mem.startsWith(u8, type_s, "const ")) try self.w("const ");
        try self.w(type_s);
        try self.w(" ");
        try self.w(name);
        if (node.data.rhs != null_node) {
            try self.w(" = ");
            try self.emitExpr(node.data.rhs);
        }
        try self.w(";\n");
    }

    fn emitIfStmt(self: *CodeGenCuda, node: Node) !void {
        try self.writeIndent();
        try self.w("if (");
        try self.emitExpr(node.data.lhs);
        try self.w(") ");
        try self.emitBlock(node.data.rhs);
        const else_node = self.tree.extra.items[node.data.extra];
        if (else_node != null_node) {
            const en = self.tree.nodes.items[else_node];
            if (en.tag == .if_stmt) {
                try self.w(" else ");
                try self.emitIfStmt(en);
            } else {
                try self.w(" else ");
                try self.emitBlock(else_node);
                try self.w("\n");
            }
        } else try self.w("\n");
    }

    fn emitForStmt(self: *CodeGenCuda, node: Node) !void {
        const es = node.data.lhs;
        const init_n = self.tree.extra.items[es];
        const cond_n = self.tree.extra.items[es + 1];
        const upd_n = self.tree.extra.items[es + 2];
        try self.writeIndent();
        try self.w("for (");
        if (init_n != null_node) {
            const inode = self.tree.nodes.items[init_n];
            if (inode.tag == .var_decl) try self.emitVarDeclInline(inode) else try self.emitExpr(init_n);
        }
        try self.w("; ");
        if (cond_n != null_node) try self.emitExpr(cond_n);
        try self.w("; ");
        if (upd_n != null_node) try self.emitExpr(upd_n);
        try self.w(") ");
        try self.emitBlock(node.data.rhs);
        try self.w("\n");
    }

    fn emitVarDeclInline(self: *CodeGenCuda, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const tn = self.tree.extra.items[node.data.extra];
        try self.w(if (tn != null_node) self.typeStr(tn) else "double");
        try self.w(" ");
        try self.w(name);
        if (node.data.rhs != null_node) {
            try self.w(" = ");
            try self.emitExpr(node.data.rhs);
        }
    }

    fn emitBlock(self: *CodeGenCuda, idx: NodeIndex) anyerror!void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        if (node.tag != .block) {
            try self.emitStmt(idx);
            return;
        }
        try self.w("{\n");
        self.indent += 1;
        var i: u32 = 0;
        while (i < node.data.rhs) : (i += 1)
            try self.emitStmt(self.tree.extra.items[node.data.lhs + i]);
        self.indent -= 1;
        try self.writeIndent();
        try self.w("}");
    }

    fn emitExpr(self: *CodeGenCuda, idx: NodeIndex) !void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        switch (node.tag) {
            .number_lit, .string_lit => try self.w(self.tree.getString(unpackStringRef(node.data.lhs))),
            .identifier => try self.w(self.tree.getString(unpackStringRef(node.data.lhs))),
            .bool_lit => try self.w(if (node.data.lhs != 0) "true" else "false"),
            .binary_expr => {
                const op: Op = @enumFromInt(self.tree.extra.items[node.data.extra]);
                try self.w("(");
                try self.emitExpr(node.data.lhs);
                try self.w(opStr(op));
                try self.emitExpr(node.data.rhs);
                try self.w(")");
            },
            .unary_expr => {
                const op: Op = @enumFromInt(node.data.rhs);
                try self.w(if (op == .logical_not) "!" else "-");
                try self.emitExpr(node.data.lhs);
            },
            .assign_expr => {
                try self.emitExpr(node.data.lhs);
                const op: Op = @enumFromInt(self.tree.extra.items[node.data.extra]);
                try self.w(assignStr(op));
                try self.emitExpr(node.data.rhs);
            },
            .call_expr => {
                try self.emitExpr(node.data.lhs);
                try self.w("(");
                const es = node.data.rhs;
                const ac = self.tree.extra.items[es];
                var ai: u32 = 0;
                while (ai < ac) : (ai += 1) {
                    if (ai > 0) try self.w(", ");
                    try self.emitExpr(self.tree.extra.items[es + 1 + ai]);
                }
                try self.w(")");
            },
            .member_expr => {
                try self.emitExpr(node.data.lhs);
                try self.w(".");
                try self.w(self.tree.getString(unpackStringRef(node.data.rhs)));
            },
            .index_expr => {
                try self.emitExpr(node.data.lhs);
                try self.w("[");
                try self.emitExpr(node.data.rhs);
                try self.w("]");
            },
            .array_lit => {
                try self.w("{ ");
                var ei: u32 = 0;
                while (ei < node.data.rhs) : (ei += 1) {
                    if (ei > 0) try self.w(", ");
                    try self.emitExpr(self.tree.extra.items[node.data.lhs + ei]);
                }
                try self.w(" }");
            },
            .object_lit => {
                try self.w("{ ");
                var oi: u32 = 0;
                while (oi < node.data.rhs) : (oi += 1) {
                    if (oi > 0) try self.w(", ");
                    try self.w(".");
                    try self.w(self.tree.getString(unpackStringRef(self.tree.extra.items[node.data.lhs + oi * 2])));
                    try self.w(" = ");
                    try self.emitExpr(self.tree.extra.items[node.data.lhs + oi * 2 + 1]);
                }
                try self.w(" }");
            },
            else => try self.w("/* unsupported */"),
        }
    }

    fn tryEmitConsoleLog(self: *CodeGenCuda, idx: NodeIndex) !bool {
        if (idx == null_node) return false;
        const node = self.tree.nodes.items[idx];
        if (node.tag != .call_expr) return false;
        const callee = self.tree.nodes.items[node.data.lhs];
        if (callee.tag != .member_expr) return false;
        const obj = self.tree.nodes.items[callee.data.lhs];
        if (obj.tag != .identifier) return false;
        if (!std.mem.eql(u8, self.tree.getString(unpackStringRef(obj.data.lhs)), "console")) return false;
        if (!std.mem.eql(u8, self.tree.getString(unpackStringRef(callee.data.rhs)), "log")) return false;
        const es = node.data.rhs;
        const ac = self.tree.extra.items[es];
        try self.writeIndent();
        try self.w("printf(\"");
        var ai: u32 = 0;
        while (ai < ac) : (ai += 1) {
            if (ai > 0) try self.w(" ");
            try self.w(self.inferFmt(self.tree.extra.items[es + 1 + ai]));
        }
        try self.w("\\n\"");
        ai = 0;
        while (ai < ac) : (ai += 1) {
            try self.w(", ");
            try self.emitExpr(self.tree.extra.items[es + 1 + ai]);
        }
        try self.w(");\n");
        return true;
    }

    fn inferFmt(self: *CodeGenCuda, idx: NodeIndex) []const u8 {
        if (idx == null_node) return "%g";
        const node = self.tree.nodes.items[idx];
        return switch (node.tag) {
            .number_lit => "%g",
            .string_lit => "%s",
            .bool_lit => "%d",
            .identifier => blk: {
                const name = self.tree.getString(unpackStringRef(node.data.lhs));
                if (self.checker.lookupSymbol(name)) |sym| break :blk switch (sym.type_info.base) {
                    .number, .f64_t, .f32_t => "%g",
                    .i32_t, .i64_t => "%d",
                    .string => "%s",
                    .boolean => "%d",
                    else => "%g",
                };
                break :blk "%g";
            },
            else => "%g",
        };
    }

    fn typeStr(self: *CodeGenCuda, idx: NodeIndex) []const u8 {
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
            return name;
        }
        if (node.tag == .type_array) {
            // Map typed arrays to CUDA pointer types
            const elem = self.tree.nodes.items[node.data.lhs];
            if (elem.tag == .type_name) {
                const ename = self.tree.getString(unpackStringRef(elem.data.lhs));
                if (std.mem.eql(u8, ename, "f32")) return "float*";
                if (std.mem.eql(u8, ename, "f64")) return "double*";
                if (std.mem.eql(u8, ename, "i32")) return "int32_t*";
                if (std.mem.eql(u8, ename, "i64")) return "int64_t*";
            }
            return "double*";
        }
        return "double";
    }

    fn w(self: *CodeGenCuda, s: []const u8) !void {
        try self.out.appendSlice(self.allocator, s);
    }

    fn writeIndent(self: *CodeGenCuda) !void {
        var i: u32 = 0;
        while (i < self.indent) : (i += 1)
            try self.out.appendSlice(self.allocator, "    ");
    }

    fn opStr(op: Op) []const u8 {
        return switch (op) {
            .add => " + ", .sub => " - ", .mul => " * ", .div => " / ", .mod => " % ",
            .eq, .strict_eq => " == ", .neq, .strict_neq => " != ",
            .lt => " < ", .gt => " > ", .lte => " <= ", .gte => " >= ",
            .logical_and => " && ", .logical_or => " || ",
            else => " ? ",
        };
    }

    fn assignStr(op: Op) []const u8 {
        return switch (op) {
            .assign => " = ", .add_assign => " += ", .sub_assign => " -= ",
            .mul_assign => " *= ", .div_assign => " /= ",
            else => " = ",
        };
    }
};
