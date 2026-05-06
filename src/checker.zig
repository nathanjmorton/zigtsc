const std = @import("std");
const ast_mod = @import("ast.zig");
const Ast = ast_mod.Ast;
const Node = ast_mod.Node;
const NodeIndex = ast_mod.NodeIndex;
const null_node = ast_mod.null_node;
const unpackStringRef = ast_mod.unpackStringRef;

pub const Type = enum {
    number, i32_t, i64_t, f32_t, f64_t, boolean, string, void_t,
    struct_t, array_t, unknown, err,
};

pub const TypeInfo = struct { base: Type, detail: u32 = 0 };
pub const StructDef = struct { name: []const u8, fields: []const FieldDef };
pub const FieldDef = struct { name: []const u8, type_info: TypeInfo };
pub const Symbol = struct { name: []const u8, type_info: TypeInfo, is_const: bool };
pub const FuncSig = struct { name: []const u8, params: []const ParamSig, return_type: TypeInfo };
pub const ParamSig = struct { name: []const u8, type_info: TypeInfo };

pub const Checker = struct {
    tree: *const Ast,
    allocator: std.mem.Allocator,
    errors: std.ArrayList(Error) = .empty,
    scopes: std.ArrayList(std.StringHashMapUnmanaged(Symbol)) = .empty,
    structs: std.ArrayList(StructDef) = .empty,
    functions: std.StringHashMapUnmanaged(FuncSig) = .empty,

    pub const Error = struct { msg: []const u8 };

    pub fn init(tree: *const Ast, allocator: std.mem.Allocator) Checker {
        var c = Checker{ .tree = tree, .allocator = allocator };
        var global: std.StringHashMapUnmanaged(Symbol) = .empty;
        _ = &global;
        c.scopes.append(allocator, global) catch {};
        return c;
    }

    pub fn deinit(self: *Checker) void {
        for (self.scopes.items) |*s| s.deinit(self.allocator);
        self.scopes.deinit(self.allocator);
        self.errors.deinit(self.allocator);
        for (self.structs.items) |s| self.allocator.free(s.fields);
        self.structs.deinit(self.allocator);
        var it = self.functions.iterator();
        while (it.next()) |entry| self.allocator.free(entry.value_ptr.params);
        self.functions.deinit(self.allocator);
    }

    pub fn check(self: *Checker, root: NodeIndex) !void {
        const node = self.tree.nodes.items[root];
        if (node.tag != .program) return;
        const start = node.data.lhs;
        const count = node.data.rhs;
        var i: u32 = 0;
        while (i < count) : (i += 1) try self.checkNode(self.tree.extra.items[start + i]);
    }

    fn checkNode(self: *Checker, idx: NodeIndex) anyerror!void {
        if (idx == null_node) return;
        const node = self.tree.nodes.items[idx];
        switch (node.tag) {
            .var_decl => try self.checkVarDecl(node),
            .func_decl => try self.checkFuncDecl(node),
            .interface_decl => try self.checkInterfaceDecl(node),
            .if_stmt => { _ = try self.resolveExprType(node.data.lhs); try self.checkNode(node.data.rhs); const e = self.tree.extra.items[node.data.extra]; if (e != null_node) try self.checkNode(e); },
            .while_stmt => { _ = try self.resolveExprType(node.data.lhs); try self.checkNode(node.data.rhs); },
            .for_stmt => { const es = node.data.lhs; try self.checkNode(self.tree.extra.items[es]); try self.checkNode(node.data.rhs); },
            .expr_stmt => _ = try self.resolveExprType(node.data.lhs),
            .block => { const s = node.data.lhs; const c = node.data.rhs; var i: u32 = 0; while (i < c) : (i += 1) try self.checkNode(self.tree.extra.items[s + i]); },
            else => {},
        }
    }

    fn checkVarDecl(self: *Checker, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const type_node = self.tree.extra.items[es];
        const is_const = self.tree.extra.items[es + 1] != 0;
        var ti = TypeInfo{ .base = .unknown };
        if (type_node != null_node) ti = self.resolveTypeNode(type_node)
        else if (node.data.rhs != null_node) ti = try self.resolveExprType(node.data.rhs);
        try self.define(name, .{ .name = name, .type_info = ti, .is_const = is_const });
    }

    fn checkFuncDecl(self: *Checker, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.extra;
        const ret_type_node = self.tree.extra.items[es];
        const param_count = self.tree.extra.items[es + 1];
        var ret = TypeInfo{ .base = .void_t };
        if (ret_type_node != null_node) ret = self.resolveTypeNode(ret_type_node);
        var params: std.ArrayList(ParamSig) = .empty;
        defer params.deinit(self.allocator);
        var i: u32 = 0;
        while (i < param_count) : (i += 1) {
            const pnode = self.tree.nodes.items[self.tree.extra.items[es + 2 + i]];
            const pname = self.tree.getString(unpackStringRef(pnode.data.lhs));
            try params.append(self.allocator, .{ .name = pname, .type_info = self.resolveTypeNode(pnode.data.rhs) });
        }
        try self.functions.put(self.allocator, name, .{
            .name = name,
            .params = try self.allocator.dupe(ParamSig, params.items),
            .return_type = ret,
        });
        try self.scopes.append(self.allocator, std.StringHashMapUnmanaged(Symbol).empty);
        for (params.items) |p| try self.define(p.name, .{ .name = p.name, .type_info = p.type_info, .is_const = false });
        try self.checkNode(node.data.rhs);
        var scope = self.scopes.pop().?;
        scope.deinit(self.allocator);
    }

    fn checkInterfaceDecl(self: *Checker, node: Node) !void {
        const name = self.tree.getString(unpackStringRef(node.data.lhs));
        const es = node.data.rhs;
        const field_count = self.tree.extra.items[es];
        var fields: std.ArrayList(FieldDef) = .empty;
        defer fields.deinit(self.allocator);
        var i: u32 = 0;
        while (i < field_count) : (i += 1) {
            const fnode = self.tree.nodes.items[self.tree.extra.items[es + 1 + i]];
            const fname = self.tree.getString(unpackStringRef(fnode.data.lhs));
            try fields.append(self.allocator, .{ .name = fname, .type_info = self.resolveTypeNode(fnode.data.rhs) });
        }
        try self.structs.append(self.allocator, .{ .name = name, .fields = try self.allocator.dupe(FieldDef, fields.items) });
    }

    fn resolveTypeNode(self: *Checker, idx: NodeIndex) TypeInfo {
        if (idx == null_node) return .{ .base = .unknown };
        const node = self.tree.nodes.items[idx];
        if (node.tag == .type_name) {
            const name = self.tree.getString(unpackStringRef(node.data.lhs));
            if (std.mem.eql(u8, name, "number")) return .{ .base = .number };
            if (std.mem.eql(u8, name, "boolean")) return .{ .base = .boolean };
            if (std.mem.eql(u8, name, "string")) return .{ .base = .string };
            if (std.mem.eql(u8, name, "void")) return .{ .base = .void_t };
            if (std.mem.eql(u8, name, "i32")) return .{ .base = .i32_t };
            if (std.mem.eql(u8, name, "i64")) return .{ .base = .i64_t };
            if (std.mem.eql(u8, name, "f32")) return .{ .base = .f32_t };
            if (std.mem.eql(u8, name, "f64")) return .{ .base = .f64_t };
            for (self.structs.items, 0..) |s, si| if (std.mem.eql(u8, s.name, name)) return .{ .base = .struct_t, .detail = @intCast(si) };
            return .{ .base = .unknown };
        }
        if (node.tag == .type_array) return .{ .base = .array_t };
        return .{ .base = .unknown };
    }

    fn resolveExprType(self: *Checker, idx: NodeIndex) !TypeInfo {
        if (idx == null_node) return .{ .base = .unknown };
        const node = self.tree.nodes.items[idx];
        return switch (node.tag) {
            .number_lit => .{ .base = .number },
            .string_lit => .{ .base = .string },
            .bool_lit => .{ .base = .boolean },
            .identifier => blk: { if (self.lookup(self.tree.getString(unpackStringRef(node.data.lhs)))) |sym| break :blk sym.type_info; break :blk .{ .base = .unknown }; },
            .binary_expr => blk: { const l = try self.resolveExprType(node.data.lhs); _ = try self.resolveExprType(node.data.rhs); break :blk l; },
            .assign_expr => try self.resolveExprType(node.data.rhs),
            .unary_expr => try self.resolveExprType(node.data.lhs),
            else => .{ .base = .unknown },
        };
    }

    fn define(self: *Checker, name: []const u8, sym: Symbol) !void {
        if (self.scopes.items.len > 0) try self.scopes.items[self.scopes.items.len - 1].put(self.allocator, name, sym);
    }

    fn lookup(self: *Checker, name: []const u8) ?Symbol {
        var i: usize = self.scopes.items.len;
        while (i > 0) { i -= 1; if (self.scopes.items[i].get(name)) |sym| return sym; }
        return null;
    }

    pub fn lookupSymbol(self: *const Checker, name: []const u8) ?Symbol {
        var i: usize = self.scopes.items.len;
        while (i > 0) { i -= 1; if (self.scopes.items[i].get(name)) |sym| return sym; }
        return null;
    }

    pub fn lookupFunc(self: *const Checker, name: []const u8) ?FuncSig { return self.functions.get(name); }
};
