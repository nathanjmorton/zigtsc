const std = @import("std");
const ast_mod = @import("ast.zig");
const Node = ast_mod.Node;
const NodeIndex = ast_mod.NodeIndex;
const null_node = ast_mod.null_node;
const Op = ast_mod.Op;
const unpackStringRef = ast_mod.unpackStringRef;

pub const CodeGenJS = struct {
    tree: *const ast_mod.Ast,
    out: std.ArrayList(u8) = .empty,
    indent: u32 = 0,
    allocator: std.mem.Allocator,

    pub fn init(tree: *const ast_mod.Ast, allocator: std.mem.Allocator) CodeGenJS {
        return .{ .tree = tree, .allocator = allocator };
    }

    pub fn deinit(self: *CodeGenJS) void { self.out.deinit(self.allocator); }

    pub fn generate(self: *CodeGenJS, root: NodeIndex) ![]const u8 {
        const node = self.tree.nodes.items[root];
        if (node.tag != .program) return "";
        const start = node.data.lhs;
        const count = node.data.rhs;
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const idx = self.tree.extra.items[start + i];
            const s = self.tree.nodes.items[idx];
            switch (s.tag) {
                .interface_decl => {}, // interfaces are compile-time only — omit
                .class_decl => try self.emitClassDecl(s),
                .func_decl => { try self.emitFuncDecl(s); try self.w("\n"); },
                else => try self.emitStmt(idx),
            }
        }
        return self.out.items;
    }

    fn emitClassDecl(self: *CodeGenJS, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        const ctor_node = self.tree.extra.items[es + 1 + field_count];
        const method_count = self.tree.extra.items[es + 2 + field_count];

        try self.w("class "); try self.w(name); try self.w(" {\n");
        self.indent += 1;

        // Constructor
        if (ctor_node != null_node) {
            const cnode = self.tree.nodes.items[ctor_node];
            const ces = cnode.data.lhs;
            const pc = self.tree.extra.items[ces];
            try self.writeIndent(); try self.w("constructor(");
            var pi: u32 = 0;
            while (pi < pc) : (pi += 1) {
                if (pi > 0) try self.w(", ");
                const pnode = self.tree.nodes.items[self.tree.extra.items[ces + 1 + pi]];
                try self.w(self.tree.getString(unpackStringRef(pnode.data.lhs)));
            }
            try self.w(") ");
            try self.emitBlock(cnode.data.rhs);
            try self.w("\n");
        }

        // Methods
        var i: u32 = 0;
        while (i < method_count) : (i += 1) {
            const mnode = self.tree.nodes.items[self.tree.extra.items[es + 3 + field_count + i]];
            const mname = self.tree.getString(unpackStringRef(mnode.data.lhs));
            const mes = mnode.data.extra;
            const mpc = self.tree.extra.items[mes + 1];
            try self.writeIndent(); try self.w(mname); try self.w("(");
            var mi: u32 = 0;
            while (mi < mpc) : (mi += 1) {
                if (mi > 0) try self.w(", ");
                const mpnode = self.tree.nodes.items[self.tree.extra.items[mes + 2 + mi]];
                try self.w(self.tree.getString(unpackStringRef(mpnode.data.lhs)));
            }
            try self.w(") ");
            try self.emitBlock(mnode.data.rhs);
            try self.w("\n");
        }

        self.indent -= 1;
        try self.w("}\n\n");
    }

    fn emitFuncDecl(self: *CodeGenJS, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const pc = self.tree.extra.items[es + 1];
        try self.w("function "); try self.w(name); try self.w("(");
        var pi: u32 = 0;
        while (pi < pc) : (pi += 1) {
            if (pi > 0) try self.w(", ");
            const p = self.tree.nodes.items[self.tree.extra.items[es + 2 + pi]];
            try self.w(self.tree.getString(unpackStringRef(p.data.lhs)));
        }
        try self.w(") ");
        try self.emitBlock(node.data.rhs);
        try self.w("\n");
    }

    fn emitStmt(self: *CodeGenJS, idx: NodeIndex) anyerror!void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        switch (node.tag) {
            .var_decl => try self.emitVarDecl(node),
            .if_stmt => try self.emitIfStmt(node),
            .while_stmt => { try self.writeIndent(); try self.w("while ("); try self.emitExpr(node.data.lhs); try self.w(") "); try self.emitBlock(node.data.rhs); try self.w("\n"); },
            .for_stmt => try self.emitForStmt(node),
            .return_stmt => { try self.writeIndent(); if (node.data.lhs != null_node) { try self.w("return "); try self.emitExpr(node.data.lhs); try self.w(";\n"); } else try self.w("return;\n"); },
            .expr_stmt => { try self.writeIndent(); try self.emitExpr(node.data.lhs); try self.w(";\n"); },
            .block => try self.emitBlock(idx),
            else => {},
        }
    }

    fn emitVarDecl(self: *CodeGenJS, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const is_const = self.tree.extra.items[es + 1] != 0;
        try self.writeIndent();
        try self.w(if (is_const) "const " else "let ");
        try self.w(name);
        if (node.data.rhs != null_node) { try self.w(" = "); try self.emitExpr(node.data.rhs); }
        try self.w(";\n");
    }

    fn emitIfStmt(self: *CodeGenJS, node: Node) !void {
        try self.writeIndent(); try self.w("if ("); try self.emitExpr(node.data.lhs); try self.w(") ");
        try self.emitBlock(node.data.rhs);
        const else_node = self.tree.extra.items[node.data.extra];
        if (else_node != null_node) {
            const en = self.tree.nodes.items[else_node];
            if (en.tag == .if_stmt) { try self.w(" else "); try self.emitIfStmt(en); } else { try self.w(" else "); try self.emitBlock(else_node); try self.w("\n"); }
        } else try self.w("\n");
    }

    fn emitForStmt(self: *CodeGenJS, node: Node) !void {
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

    fn emitVarDeclInline(self: *CodeGenJS, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const is_const = self.tree.extra.items[es + 1] != 0;
        try self.w(if (is_const) "const " else "let ");
        try self.w(name);
        if (node.data.rhs != null_node) { try self.w(" = "); try self.emitExpr(node.data.rhs); }
    }

    fn emitBlock(self: *CodeGenJS, idx: NodeIndex) anyerror!void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        if (node.tag != .block) { try self.emitStmt(idx); return; }
        try self.w("{\n"); self.indent += 1;
        var i: u32 = 0; while (i < node.data.rhs) : (i += 1) try self.emitStmt(self.tree.extra.items[node.data.lhs + i]);
        self.indent -= 1; try self.writeIndent(); try self.w("}");
    }

    fn emitExpr(self: *CodeGenJS, idx: NodeIndex) !void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        switch (node.tag) {
            .number_lit, .identifier => try self.w(self.tree.getString(unpackStringRef(node.data.lhs))),
            .string_lit => try self.w(self.tree.getString(unpackStringRef(node.data.lhs))),
            .bool_lit => try self.w(if (node.data.lhs != 0) "true" else "false"),
            .this_expr => try self.w("this"),
            .new_expr => {
                const cname = self.tree.getString(unpackStringRef(node.data.lhs));
                try self.w("new "); try self.w(cname); try self.w("(");
                const aes = node.data.rhs; const ac = self.tree.extra.items[aes];
                var ai: u32 = 0;
                while (ai < ac) : (ai += 1) { if (ai > 0) try self.w(", "); try self.emitExpr(self.tree.extra.items[aes + 1 + ai]); }
                try self.w(")");
            },
            .binary_expr => { const op: Op = @enumFromInt(self.tree.extra.items[node.data.extra]); try self.w("("); try self.emitExpr(node.data.lhs); try self.w(opStr(op)); try self.emitExpr(node.data.rhs); try self.w(")"); },
            .unary_expr => { const op: Op = @enumFromInt(node.data.rhs); try self.w(if (op == .logical_not) "!" else "-"); try self.emitExpr(node.data.lhs); },
            .assign_expr => { try self.emitExpr(node.data.lhs); const op: Op = @enumFromInt(self.tree.extra.items[node.data.extra]); try self.w(assignStr(op)); try self.emitExpr(node.data.rhs); },
            .call_expr => { try self.emitExpr(node.data.lhs); try self.w("("); const aes = node.data.rhs; const ac = self.tree.extra.items[aes]; var ai: u32 = 0; while (ai < ac) : (ai += 1) { if (ai > 0) try self.w(", "); try self.emitExpr(self.tree.extra.items[aes + 1 + ai]); } try self.w(")"); },
            .member_expr => { try self.emitExpr(node.data.lhs); try self.w("."); try self.w(self.tree.getString(unpackStringRef(node.data.rhs))); },
            .index_expr => { try self.emitExpr(node.data.lhs); try self.w("["); try self.emitExpr(node.data.rhs); try self.w("]"); },
            .array_lit => { try self.w("["); var ei: u32 = 0; while (ei < node.data.rhs) : (ei += 1) { if (ei > 0) try self.w(", "); try self.emitExpr(self.tree.extra.items[node.data.lhs + ei]); } try self.w("]"); },
            .object_lit => { try self.w("{ "); var oi: u32 = 0; while (oi < node.data.rhs) : (oi += 1) { if (oi > 0) try self.w(", "); try self.w(self.tree.getString(unpackStringRef(self.tree.extra.items[node.data.lhs + oi * 2]))); try self.w(": "); try self.emitExpr(self.tree.extra.items[node.data.lhs + oi * 2 + 1]); } try self.w(" }"); },
            else => try self.w("/* unsupported */"),
        }
    }

    fn w(self: *CodeGenJS, s: []const u8) !void { try self.out.appendSlice(self.allocator, s); }
    fn writeIndent(self: *CodeGenJS) !void { var i: u32 = 0; while (i < self.indent) : (i += 1) try self.out.appendSlice(self.allocator, "    "); }

    fn opStr(op: Op) []const u8 {
        return switch (op) { .add => " + ", .sub => " - ", .mul => " * ", .div => " / ", .mod => " % ", .eq => " == ", .strict_eq => " === ", .neq => " != ", .strict_neq => " !== ", .lt => " < ", .gt => " > ", .lte => " <= ", .gte => " >= ", .logical_and => " && ", .logical_or => " || ", else => " ? " };
    }
    fn assignStr(op: Op) []const u8 {
        return switch (op) { .assign => " = ", .add_assign => " += ", .sub_assign => " -= ", .mul_assign => " *= ", .div_assign => " /= ", else => " = " };
    }
};
