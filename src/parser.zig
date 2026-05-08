const std = @import("std");
const Token = @import("token.zig").Token;
const Lexer = @import("lexer.zig").Lexer;
const ast_mod = @import("ast.zig");
const Ast = ast_mod.Ast;
const Node = ast_mod.Node;
const NodeIndex = ast_mod.NodeIndex;
const null_node = ast_mod.null_node;
const Op = ast_mod.Op;
const packStringRef = ast_mod.packStringRef;

pub const Parser = struct {
    lexer: Lexer,
    tree: Ast,
    current: Token,
    prev: Token,
    allocator: std.mem.Allocator,
    errors: std.ArrayList(Error) = .empty,

    pub const Error = struct { msg: []const u8, loc: Token.Loc };

    pub fn init(source: []const u8, allocator: std.mem.Allocator) Parser {
        var lexer = Lexer.init(source);
        const first = lexer.next();
        return .{
            .lexer = lexer,
            .tree = Ast.init(allocator, source),
            .current = first,
            .prev = first,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.errors.deinit(self.allocator);
    }

    pub fn parse(self: *Parser) !NodeIndex {
        var stmts: std.ArrayList(NodeIndex) = .empty;
        defer stmts.deinit(self.allocator);
        while (self.current.tag != .eof) {
            const stmt = try self.parseTopLevel();
            if (stmt != null_node) try stmts.append(self.allocator, stmt);
        }
        const extra_start = try self.tree.addExtraSlice(stmts.items);
        return self.tree.addNode(.{
            .tag = .program,
            .data = .{ .lhs = extra_start, .rhs = @intCast(stmts.items.len) },
        });
    }

    fn parseTopLevel(self: *Parser) !NodeIndex {
        if (self.current.tag == .kw_export) self.bump();
        return switch (self.current.tag) {
            .kw_function => self.parseFuncDecl(),
            .kw_interface => self.parseInterfaceDecl(),
            .kw_class => self.parseClassDecl(),
            .kw_type => self.parseTypeAlias(),
            .kw_let, .kw_const => self.parseVarDecl(),
            else => self.parseStatement(),
        };
    }

    fn parseFuncDecl(self: *Parser) !NodeIndex {
        self.bump();
        const name_ref = try self.expectIdentString();
        try self.expect(.lparen);
        var params: std.ArrayList(NodeIndex) = .empty;
        defer params.deinit(self.allocator);
        while (self.current.tag != .rparen and self.current.tag != .eof) {
            const pname = try self.expectIdentString();
            try self.expect(.colon);
            const ptype = try self.parseTypeAnnotation();
            try params.append(self.allocator, try self.tree.addNode(.{
                .tag = .param, .data = .{ .lhs = packStringRef(pname), .rhs = ptype },
            }));
            if (self.current.tag == .comma) self.bump();
        }
        try self.expect(.rparen);
        var ret_type: NodeIndex = null_node;
        if (self.current.tag == .colon) { self.bump(); ret_type = try self.parseTypeAnnotation(); }
        const body = try self.parseBlock();
        const extra_start = try self.tree.addExtra(ret_type);
        _ = try self.tree.addExtra(@intCast(params.items.len));
        for (params.items) |p| _ = try self.tree.addExtra(p);
        return self.tree.addNode(.{
            .tag = .func_decl,
            .data = .{ .lhs = packStringRef(name_ref), .rhs = body, .extra = extra_start },
        });
    }

    fn parseInterfaceDecl(self: *Parser) !NodeIndex {
        self.bump();
        const name_ref = try self.expectIdentString();
        try self.expect(.lbrace);
        var fields: std.ArrayList(NodeIndex) = .empty;
        defer fields.deinit(self.allocator);
        while (self.current.tag != .rbrace and self.current.tag != .eof) {
            const fname = try self.expectIdentString();
            if (self.current.tag == .question_mark) self.bump();
            try self.expect(.colon);
            const ftype = try self.parseTypeAnnotation();
            try fields.append(self.allocator, try self.tree.addNode(.{
                .tag = .field, .data = .{ .lhs = packStringRef(fname), .rhs = ftype },
            }));
            if (self.current.tag == .semicolon) self.bump();
            if (self.current.tag == .comma) self.bump();
        }
        try self.expect(.rbrace);
        const extra_start = try self.tree.addExtra(@intCast(fields.items.len));
        for (fields.items) |f| _ = try self.tree.addExtra(f);
        return self.tree.addNode(.{
            .tag = .interface_decl,
            .data = .{ .lhs = packStringRef(name_ref), .rhs = extra_start },
        });
    }

    /// Parses: class Name { field: Type; constructor(...) { } methodName(...): RetType { } }
    /// Extra data layout: [field_count, field_nodes..., constructor_node, method_count, method_nodes...]
    fn parseClassDecl(self: *Parser) !NodeIndex {
        self.bump(); // consume 'class'
        const name_ref = try self.expectIdentString();
        try self.expect(.lbrace);

        var fields: std.ArrayList(NodeIndex) = .empty;
        defer fields.deinit(self.allocator);
        var methods: std.ArrayList(NodeIndex) = .empty;
        defer methods.deinit(self.allocator);
        var constructor_node: NodeIndex = null_node;

        while (self.current.tag != .rbrace and self.current.tag != .eof) {
            // Check if this is the constructor
            if (self.current.tag == .identifier and std.mem.eql(u8, self.current.slice(self.tree.source), "constructor")) {
                constructor_node = try self.parseConstructorDecl();
                continue;
            }
            // Peek ahead: if next token after identifier is '(' it's a method, otherwise a field
            if (self.current.tag == .identifier) {
                const saved_pos = self.lexer.pos;
                const saved_current = self.current;
                const saved_prev = self.prev;
                self.bump(); // consume identifier
                if (self.current.tag == .lparen) {
                    // It's a method — restore and parse as method
                    self.lexer.pos = saved_pos;
                    self.current = saved_current;
                    self.prev = saved_prev;
                    try methods.append(self.allocator, try self.parseMethodDecl());
                } else {
                    // It's a field — restore and parse as field
                    self.lexer.pos = saved_pos;
                    self.current = saved_current;
                    self.prev = saved_prev;
                    try fields.append(self.allocator, try self.parseClassField());
                }
                continue;
            }
            // Skip unexpected tokens
            self.bump();
        }
        try self.expect(.rbrace);

        // Pack extra data: field_count, fields..., constructor_node, method_count, methods...
        const extra_start = try self.tree.addExtra(@intCast(fields.items.len));
        for (fields.items) |f| _ = try self.tree.addExtra(f);
        _ = try self.tree.addExtra(constructor_node);
        _ = try self.tree.addExtra(@intCast(methods.items.len));
        for (methods.items) |m| _ = try self.tree.addExtra(m);

        return self.tree.addNode(.{
            .tag = .class_decl,
            .data = .{ .lhs = packStringRef(name_ref), .rhs = extra_start },
        });
    }

    /// Parses: fieldName: Type;
    fn parseClassField(self: *Parser) !NodeIndex {
        const fname = try self.expectIdentString();
        try self.expect(.colon);
        const ftype = try self.parseTypeAnnotation();
        if (self.current.tag == .semicolon) self.bump();
        return self.tree.addNode(.{
            .tag = .field, .data = .{ .lhs = packStringRef(fname), .rhs = ftype },
        });
    }

    /// Parses: constructor(params...) { body }
    fn parseConstructorDecl(self: *Parser) !NodeIndex {
        self.bump(); // consume 'constructor' identifier
        try self.expect(.lparen);
        var params: std.ArrayList(NodeIndex) = .empty;
        defer params.deinit(self.allocator);
        while (self.current.tag != .rparen and self.current.tag != .eof) {
            const pname = try self.expectIdentString();
            try self.expect(.colon);
            const ptype = try self.parseTypeAnnotation();
            try params.append(self.allocator, try self.tree.addNode(.{
                .tag = .param, .data = .{ .lhs = packStringRef(pname), .rhs = ptype },
            }));
            if (self.current.tag == .comma) self.bump();
        }
        try self.expect(.rparen);
        const body = try self.parseBlock();
        // extra: param_count, param_nodes...
        const extra_start = try self.tree.addExtra(@intCast(params.items.len));
        for (params.items) |p| _ = try self.tree.addExtra(p);
        return self.tree.addNode(.{
            .tag = .constructor_decl,
            .data = .{ .lhs = extra_start, .rhs = body },
        });
    }

    /// Parses: methodName(params...): RetType { body }
    fn parseMethodDecl(self: *Parser) !NodeIndex {
        const name_ref = try self.expectIdentString();
        try self.expect(.lparen);
        var params: std.ArrayList(NodeIndex) = .empty;
        defer params.deinit(self.allocator);
        while (self.current.tag != .rparen and self.current.tag != .eof) {
            const pname = try self.expectIdentString();
            try self.expect(.colon);
            const ptype = try self.parseTypeAnnotation();
            try params.append(self.allocator, try self.tree.addNode(.{
                .tag = .param, .data = .{ .lhs = packStringRef(pname), .rhs = ptype },
            }));
            if (self.current.tag == .comma) self.bump();
        }
        try self.expect(.rparen);
        var ret_type: NodeIndex = null_node;
        if (self.current.tag == .colon) { self.bump(); ret_type = try self.parseTypeAnnotation(); }
        const body = try self.parseBlock();
        // extra: ret_type, param_count, param_nodes...
        const extra_start = try self.tree.addExtra(ret_type);
        _ = try self.tree.addExtra(@intCast(params.items.len));
        for (params.items) |p| _ = try self.tree.addExtra(p);
        return self.tree.addNode(.{
            .tag = .method_decl,
            .data = .{ .lhs = packStringRef(name_ref), .rhs = body, .extra = extra_start },
        });
    }

    fn parseTypeAlias(self: *Parser) !NodeIndex {
        self.bump();
        _ = try self.expectIdentString();
        try self.expect(.assign);
        _ = try self.parseTypeAnnotation();
        if (self.current.tag == .semicolon) self.bump();
        return null_node;
    }

    fn parseVarDecl(self: *Parser) !NodeIndex {
        const is_const: u32 = if (self.current.tag == .kw_const) 1 else 0;
        self.bump();
        const name_ref = try self.expectIdentString();
        var type_node: NodeIndex = null_node;
        if (self.current.tag == .colon) { self.bump(); type_node = try self.parseTypeAnnotation(); }
        var init_node: NodeIndex = null_node;
        if (self.current.tag == .assign) { self.bump(); init_node = try self.parseExpression(); }
        if (self.current.tag == .semicolon) self.bump();
        const extra_start = try self.tree.addExtra(type_node);
        _ = try self.tree.addExtra(is_const);
        return self.tree.addNode(.{
            .tag = .var_decl,
            .data = .{ .lhs = packStringRef(name_ref), .rhs = init_node, .extra = extra_start },
        });
    }

    fn parseStatement(self: *Parser) anyerror!NodeIndex {
        return switch (self.current.tag) {
            .kw_if => self.parseIfStmt(), .kw_while => self.parseWhileStmt(),
            .kw_for => self.parseForStmt(), .kw_return => self.parseReturnStmt(),
            .lbrace => self.parseBlock(), .kw_let, .kw_const => self.parseVarDecl(),
            else => self.parseExprStmt(),
        };
    }

    fn parseIfStmt(self: *Parser) !NodeIndex {
        self.bump();
        try self.expect(.lparen);
        const cond = try self.parseExpression();
        try self.expect(.rparen);
        const then_block = try self.parseBlockOrStmt();
        var else_block: NodeIndex = null_node;
        if (self.current.tag == .kw_else) {
            self.bump();
            else_block = if (self.current.tag == .kw_if) try self.parseIfStmt() else try self.parseBlockOrStmt();
        }
        const extra_start = try self.tree.addExtra(else_block);
        return self.tree.addNode(.{ .tag = .if_stmt, .data = .{ .lhs = cond, .rhs = then_block, .extra = extra_start } });
    }

    fn parseWhileStmt(self: *Parser) !NodeIndex {
        self.bump();
        try self.expect(.lparen);
        const cond = try self.parseExpression();
        try self.expect(.rparen);
        return self.tree.addNode(.{ .tag = .while_stmt, .data = .{ .lhs = cond, .rhs = try self.parseBlockOrStmt() } });
    }

    fn parseForStmt(self: *Parser) !NodeIndex {
        self.bump();
        try self.expect(.lparen);
        var init_node: NodeIndex = null_node;
        if (self.current.tag == .kw_let or self.current.tag == .kw_const) {
            init_node = try self.parseVarDecl();
        } else if (self.current.tag != .semicolon) {
            init_node = try self.parseExpression();
            if (self.current.tag == .semicolon) self.bump();
        } else self.bump();
        var cond_node: NodeIndex = null_node;
        if (self.current.tag != .semicolon) cond_node = try self.parseExpression();
        if (self.current.tag == .semicolon) self.bump();
        var update_node: NodeIndex = null_node;
        if (self.current.tag != .rparen) update_node = try self.parseExpression();
        try self.expect(.rparen);
        const body = try self.parseBlockOrStmt();
        const extra_start = try self.tree.addExtra(init_node);
        _ = try self.tree.addExtra(cond_node);
        _ = try self.tree.addExtra(update_node);
        return self.tree.addNode(.{ .tag = .for_stmt, .data = .{ .lhs = extra_start, .rhs = body } });
    }

    fn parseReturnStmt(self: *Parser) !NodeIndex {
        self.bump();
        var value: NodeIndex = null_node;
        if (self.current.tag != .semicolon and self.current.tag != .rbrace and self.current.tag != .eof)
            value = try self.parseExpression();
        if (self.current.tag == .semicolon) self.bump();
        return self.tree.addNode(.{ .tag = .return_stmt, .data = .{ .lhs = value } });
    }

    fn parseExprStmt(self: *Parser) !NodeIndex {
        const expr = try self.parseExpression();
        if (self.current.tag == .semicolon) self.bump();
        return self.tree.addNode(.{ .tag = .expr_stmt, .data = .{ .lhs = expr } });
    }

    fn parseBlock(self: *Parser) !NodeIndex {
        try self.expect(.lbrace);
        var stmts: std.ArrayList(NodeIndex) = .empty;
        defer stmts.deinit(self.allocator);
        while (self.current.tag != .rbrace and self.current.tag != .eof) {
            const stmt = try self.parseStatement();
            if (stmt != null_node) try stmts.append(self.allocator, stmt);
        }
        try self.expect(.rbrace);
        const extra_start = try self.tree.addExtraSlice(stmts.items);
        return self.tree.addNode(.{ .tag = .block, .data = .{ .lhs = extra_start, .rhs = @intCast(stmts.items.len) } });
    }

    fn parseBlockOrStmt(self: *Parser) anyerror!NodeIndex {
        if (self.current.tag == .lbrace) return self.parseBlock();
        const stmt = try self.parseStatement();
        const extra_start = try self.tree.addExtra(stmt);
        return self.tree.addNode(.{ .tag = .block, .data = .{ .lhs = extra_start, .rhs = 1 } });
    }

    fn parseExpression(self: *Parser) !NodeIndex { return self.parseAssignment(); }

    fn parseAssignment(self: *Parser) !NodeIndex {
        var left = try self.parseOr();
        while (true) {
            const op: Op = switch (self.current.tag) {
                .assign => .assign, .plus_assign => .add_assign, .minus_assign => .sub_assign,
                .star_assign => .mul_assign, .slash_assign => .div_assign, else => break,
            };
            self.bump();
            const right = try self.parseOr();
            const es = try self.tree.addExtra(@intFromEnum(op));
            left = try self.tree.addNode(.{ .tag = .assign_expr, .data = .{ .lhs = left, .rhs = right, .extra = es } });
        }
        return left;
    }

    fn parseBinOp(self: *Parser, comptime next_fn: *const fn (*Parser) anyerror!NodeIndex, comptime mapFn: *const fn (Token.Tag) ?Op) !NodeIndex {
        var left = try next_fn(self);
        while (true) {
            const op = mapFn(self.current.tag) orelse break;
            self.bump();
            const right = try next_fn(self);
            const es = try self.tree.addExtra(@intFromEnum(op));
            left = try self.tree.addNode(.{ .tag = .binary_expr, .data = .{ .lhs = left, .rhs = right, .extra = es } });
        }
        return left;
    }

    fn mapOr(tag: Token.Tag) ?Op { return if (tag == .pipe_pipe) .logical_or else null; }
    fn mapAnd(tag: Token.Tag) ?Op { return if (tag == .ampersand_ampersand) .logical_and else null; }
    fn mapEq(tag: Token.Tag) ?Op { return switch (tag) { .equal => .eq, .strict_equal => .strict_eq, .not_equal => .neq, .strict_not_equal => .strict_neq, else => null }; }
    fn mapCmp(tag: Token.Tag) ?Op { return switch (tag) { .less => .lt, .greater => .gt, .less_equal => .lte, .greater_equal => .gte, else => null }; }
    fn mapAdd(tag: Token.Tag) ?Op { return switch (tag) { .plus => .add, .minus => .sub, else => null }; }
    fn mapMul(tag: Token.Tag) ?Op { return switch (tag) { .star => .mul, .slash => .div, .percent => .mod, else => null }; }

    fn parseOr(self: *Parser) !NodeIndex { return self.parseBinOp(&parseAnd, &mapOr); }
    fn parseAnd(self: *Parser) !NodeIndex { return self.parseBinOp(&parseEquality, &mapAnd); }
    fn parseEquality(self: *Parser) !NodeIndex { return self.parseBinOp(&parseComparison, &mapEq); }
    fn parseComparison(self: *Parser) !NodeIndex { return self.parseBinOp(&parseAddSub, &mapCmp); }
    fn parseAddSub(self: *Parser) !NodeIndex { return self.parseBinOp(&parseMulDiv, &mapAdd); }
    fn parseMulDiv(self: *Parser) !NodeIndex { return self.parseBinOp(&parseUnary, &mapMul); }

    fn parseUnary(self: *Parser) !NodeIndex {
        if (self.current.tag == .bang) { self.bump(); return self.tree.addNode(.{ .tag = .unary_expr, .data = .{ .lhs = try self.parseUnary(), .rhs = @intFromEnum(Op.logical_not) } }); }
        if (self.current.tag == .minus) { self.bump(); return self.tree.addNode(.{ .tag = .unary_expr, .data = .{ .lhs = try self.parseUnary(), .rhs = @intFromEnum(Op.negate) } }); }
        return self.parsePostfix();
    }

    fn parsePostfix(self: *Parser) !NodeIndex {
        var left = try self.parsePrimary();
        while (true) {
            switch (self.current.tag) {
                .lparen => {
                    self.bump();
                    var args: std.ArrayList(NodeIndex) = .empty;
                    defer args.deinit(self.allocator);
                    while (self.current.tag != .rparen and self.current.tag != .eof) {
                        try args.append(self.allocator, try self.parseExpression());
                        if (self.current.tag == .comma) self.bump();
                    }
                    try self.expect(.rparen);
                    const es = try self.tree.addExtra(@intCast(args.items.len));
                    for (args.items) |a| _ = try self.tree.addExtra(a);
                    left = try self.tree.addNode(.{ .tag = .call_expr, .data = .{ .lhs = left, .rhs = es } });
                },
                .dot => { self.bump(); const m = try self.expectIdentString(); left = try self.tree.addNode(.{ .tag = .member_expr, .data = .{ .lhs = left, .rhs = packStringRef(m) } }); },
                .lbracket => { self.bump(); const idx = try self.parseExpression(); try self.expect(.rbracket); left = try self.tree.addNode(.{ .tag = .index_expr, .data = .{ .lhs = left, .rhs = idx } }); },
                else => break,
            }
        }
        return left;
    }

    fn parsePrimary(self: *Parser) !NodeIndex {
        switch (self.current.tag) {
            .number_literal, .string_literal => { const ref = try self.tree.internString(self.current.slice(self.tree.source)); self.bump(); return self.tree.addNode(.{ .tag = if (self.prev.tag == .number_literal) .number_lit else .string_lit, .data = .{ .lhs = packStringRef(ref) } }); },
            .true_literal => { self.bump(); return self.tree.addNode(.{ .tag = .bool_lit, .data = .{ .lhs = 1 } }); },
            .false_literal => { self.bump(); return self.tree.addNode(.{ .tag = .bool_lit, .data = .{ .lhs = 0 } }); },
            .kw_this => { self.bump(); return self.tree.addNode(.{ .tag = .this_expr, .data = .{} }); },
            .kw_new => return self.parseNewExpr(),
            .identifier => { const ref = try self.tree.internString(self.current.slice(self.tree.source)); self.bump(); return self.tree.addNode(.{ .tag = .identifier, .data = .{ .lhs = packStringRef(ref) } }); },
            .lbracket => return self.parseArrayLiteral(),
            .lbrace => return self.parseObjectLiteral(),
            .lparen => { self.bump(); const expr = try self.parseExpression(); try self.expect(.rparen); return expr; },
            else => { try self.errors.append(self.allocator, .{ .msg = "unexpected token", .loc = self.current.loc }); self.bump(); return null_node; },
        }
    }

    /// Parses: new ClassName(args...)
    fn parseNewExpr(self: *Parser) !NodeIndex {
        self.bump(); // consume 'new'
        const class_name = try self.expectIdentString();
        try self.expect(.lparen);
        var args: std.ArrayList(NodeIndex) = .empty;
        defer args.deinit(self.allocator);
        while (self.current.tag != .rparen and self.current.tag != .eof) {
            try args.append(self.allocator, try self.parseExpression());
            if (self.current.tag == .comma) self.bump();
        }
        try self.expect(.rparen);
        const es = try self.tree.addExtra(@intCast(args.items.len));
        for (args.items) |a| _ = try self.tree.addExtra(a);
        return self.tree.addNode(.{ .tag = .new_expr, .data = .{ .lhs = packStringRef(class_name), .rhs = es } });
    }

    fn parseArrayLiteral(self: *Parser) !NodeIndex {
        self.bump();
        var elems: std.ArrayList(NodeIndex) = .empty;
        defer elems.deinit(self.allocator);
        while (self.current.tag != .rbracket and self.current.tag != .eof) {
            try elems.append(self.allocator, try self.parseExpression());
            if (self.current.tag == .comma) self.bump();
        }
        try self.expect(.rbracket);
        const es = try self.tree.addExtraSlice(elems.items);
        return self.tree.addNode(.{ .tag = .array_lit, .data = .{ .lhs = es, .rhs = @intCast(elems.items.len) } });
    }

    fn parseObjectLiteral(self: *Parser) !NodeIndex {
        self.bump();
        var pairs: std.ArrayList(NodeIndex) = .empty;
        defer pairs.deinit(self.allocator);
        var count: u32 = 0;
        while (self.current.tag != .rbrace and self.current.tag != .eof) {
            const key = try self.expectIdentString();
            try self.expect(.colon);
            const value = try self.parseExpression();
            try pairs.append(self.allocator, packStringRef(key));
            try pairs.append(self.allocator, value);
            count += 1;
            if (self.current.tag == .comma) self.bump();
        }
        try self.expect(.rbrace);
        const es = try self.tree.addExtraSlice(pairs.items);
        return self.tree.addNode(.{ .tag = .object_lit, .data = .{ .lhs = es, .rhs = count } });
    }

    fn parseTypeAnnotation(self: *Parser) !NodeIndex {
        const base = try self.parseBaseType();
        if (self.current.tag == .lbracket) { self.bump(); try self.expect(.rbracket); return self.tree.addNode(.{ .tag = .type_array, .data = .{ .lhs = base } }); }
        return base;
    }

    fn parseBaseType(self: *Parser) !NodeIndex {
        switch (self.current.tag) {
            .kw_number, .kw_boolean, .kw_string, .kw_void, .kw_i32, .kw_i64, .kw_f32, .kw_f64, .identifier => {
                const ref = try self.tree.internString(self.current.slice(self.tree.source));
                self.bump();
                return self.tree.addNode(.{ .tag = .type_name, .data = .{ .lhs = packStringRef(ref) } });
            },
            else => { try self.errors.append(self.allocator, .{ .msg = "expected type", .loc = self.current.loc }); return null_node; },
        }
    }

    fn bump(self: *Parser) void { self.prev = self.current; self.current = self.lexer.next(); }

    fn expect(self: *Parser, tag: Token.Tag) !void {
        if (self.current.tag == tag) { self.bump(); } else { try self.errors.append(self.allocator, .{ .msg = "unexpected token", .loc = self.current.loc }); }
    }

    fn expectIdentString(self: *Parser) !ast_mod.StringRef {
        if (self.current.tag == .identifier) { const ref = try self.tree.internString(self.current.slice(self.tree.source)); self.bump(); return ref; }
        try self.errors.append(self.allocator, .{ .msg = "expected identifier", .loc = self.current.loc });
        return .{ .offset = 0, .len = 0 };
    }
};
