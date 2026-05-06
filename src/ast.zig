const std = @import("std");

pub const NodeIndex = u32;
pub const null_node: NodeIndex = std.math.maxInt(NodeIndex);

pub const Ast = struct {
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(NodeIndex) = .empty,
    string_pool: std.ArrayList(u8) = .empty,
    source: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Ast {
        return .{ .source = source, .allocator = allocator };
    }

    pub fn deinit(self: *Ast) void {
        self.nodes.deinit(self.allocator);
        self.extra.deinit(self.allocator);
        self.string_pool.deinit(self.allocator);
    }

    pub fn addNode(self: *Ast, node: Node) !NodeIndex {
        const idx: NodeIndex = @intCast(self.nodes.items.len);
        try self.nodes.append(self.allocator, node);
        return idx;
    }

    pub fn addExtra(self: *Ast, idx: NodeIndex) !u32 {
        const pos: u32 = @intCast(self.extra.items.len);
        try self.extra.append(self.allocator, idx);
        return pos;
    }

    pub fn addExtraSlice(self: *Ast, indices: []const NodeIndex) !u32 {
        const pos: u32 = @intCast(self.extra.items.len);
        try self.extra.appendSlice(self.allocator, indices);
        return pos;
    }

    pub fn internString(self: *Ast, s: []const u8) !StringRef {
        const offset: u32 = @intCast(self.string_pool.items.len);
        try self.string_pool.appendSlice(self.allocator, s);
        return .{ .offset = offset, .len = @intCast(s.len) };
    }

    pub fn getString(self: *const Ast, ref: StringRef) []const u8 {
        return self.string_pool.items[ref.offset .. ref.offset + ref.len];
    }
};

pub const StringRef = struct { offset: u32, len: u32 };

pub const Node = struct {
    tag: Tag,
    data: Data,

    pub const Tag = enum {
        program, var_decl, func_decl, interface_decl, param, field,
        class_decl, method_decl, constructor_decl,
        if_stmt, while_stmt, for_stmt, return_stmt, expr_stmt, block,
        binary_expr, unary_expr, call_expr, member_expr, index_expr, assign_expr,
        new_expr, this_expr,
        number_lit, string_lit, bool_lit, identifier, array_lit, object_lit,
        type_name, type_array,
    };

    pub const Data = struct { lhs: u32 = 0, rhs: u32 = 0, extra: u32 = 0 };
};

pub fn packStringRef(ref: StringRef) u32 {
    return (@as(u32, ref.len) << 16) | (ref.offset & 0xFFFF);
}

pub fn unpackStringRef(val: u32) StringRef {
    return .{ .offset = val & 0xFFFF, .len = val >> 16 };
}

pub const Op = enum(u8) {
    add, sub, mul, div, mod,
    eq, neq, strict_eq, strict_neq,
    lt, gt, lte, gte,
    logical_and, logical_or, logical_not, negate,
    assign, add_assign, sub_assign, mul_assign, div_assign,
};
