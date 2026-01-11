//! HolyC Parser Implementation
//!
//! This module implements a recursive descent parser for the HolyC language.
//! Expression parsing uses Pratt parsing for handling operator precedence.
//!
//! Structure (with approximate line numbers):
//! - Token Management (lines 110-146): Token consumption and lookahead
//! - Error Handling (lines 149-195): Error reporting and synchronization
//! - Declaration Parsing (lines 197-520): Functions, classes, unions, globals
//! - Expression Parsing (lines 522-830): Pratt parser with proper precedence
//! - Type Parsing (lines 832-910): Primitives, pointers, arrays, named types
//! - Statement Parsing (lines 912-1301): Control flow, variable declarations
//! - Postfix Parsing (lines 1303-1431): Function calls, subscripts, member access
//!
//! Tests are located in parser_test.zig (68 tests covering all features)

const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const ast = @import("ast.zig");
const ops = @import("precedence.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;
const Lexer = lexer.Lexer;
const Expr = ast.Expr;
const Stmt = ast.Stmt;
const Decl = ast.Decl;
const Type = ast.Type;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const SourceLocation = ast.SourceLocation;
const Program = ast.Program;

// Precedence constants for expression parsing
const PREC_LOWEST = 1; // Lowest precedence level (assignment, comma)
const PREC_UNARY = 14; // Precedence for unary operators (-, !, *, &, etc.)
const PREC_CAST = 14; // Precedence for type casts

/// Parser errors
pub const ParserError = error{
    ParseError,
    OutOfMemory,
    InvalidCharacter,
    Overflow,
};

/// Parser for HolyC source code
/// Uses recursive descent parsing with Pratt parsing for expressions
pub const Parser = struct {
    allocator: std.mem.Allocator,
    ast_allocator: std.mem.Allocator, // Allocator for AST nodes (arena)
    lexer: *Lexer,
    current: Token,
    previous: Token,
    had_error: bool = false,
    panic_mode: bool = false,

    /// Initialize parser with a lexer
    pub fn init(allocator: std.mem.Allocator, lex: *Lexer) ParserError!Parser {
        const initial_token = Token{
            .type = .eof,
            .lexeme = "",
            .line = 0,
            .column = 0,
        };

        var parser = Parser{
            .allocator = allocator,
            .ast_allocator = allocator, // Will be set in parse()
            .lexer = lex,
            .current = initial_token,
            .previous = initial_token,
        };

        // Prime the parser with the first token
        try parser.advance();
        return parser;
    }

    /// Parse a complete program
    pub fn parse(self: *Parser) ParserError!Program {
        // Create arena for all AST allocations
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();

        // Use arena allocator for all AST nodes
        self.ast_allocator = arena.allocator();

        const empty_slice = try self.ast_allocator.alloc(Decl, 0);
        var decls = std.ArrayList(Decl).fromOwnedSlice(empty_slice);
        errdefer decls.deinit(self.ast_allocator);

        while (!self.check(.eof)) {
            if (self.parseDeclaration()) |decl| {
                try decls.append(self.ast_allocator, decl);
            } else |err| {
                if (err == error.ParseError) {
                    self.synchronize();
                } else {
                    return err;
                }
            }
        }

        return Program{
            .decls = try decls.toOwnedSlice(self.ast_allocator),
            .allocator = self.allocator,
            .arena = arena,
        };
    }

    // ============================================================================
    // Token Management
    // ============================================================================

    /// Advance to the next token
    fn advance(self: *Parser) ParserError!void {
        self.previous = self.current;

        while (true) {
            self.current = try self.lexer.nextToken();

            // Skip invalid tokens (errors already reported by lexer)
            if (self.current.type != .invalid) break;

            self.reportError("Invalid token");
        }
    }

    /// Check if current token matches given type
    fn check(self: *Parser, token_type: TokenType) bool {
        return self.current.type == token_type;
    }

    /// Consume current token if it matches, otherwise error
    fn consume(self: *Parser, token_type: TokenType, message: []const u8) ParserError!void {
        if (self.current.type == token_type) {
            try self.advance();
            return;
        }

        self.reportErrorAtCurrent(message);
        return error.ParseError;
    }

    /// Consume current token if it matches, otherwise return false
    fn match(self: *Parser, token_type: TokenType) ParserError!bool {
        if (!self.check(token_type)) return false;
        try self.advance();
        return true;
    }

    // ============================================================================
    // Error Handling
    // ============================================================================

    fn reportError(self: *Parser, message: []const u8) void {
        self.reportErrorAt(self.previous, message);
    }

    fn reportErrorAtCurrent(self: *Parser, message: []const u8) void {
        self.reportErrorAt(self.current, message);
    }

    fn reportErrorAt(self: *Parser, token: Token, message: []const u8) void {
        if (self.panic_mode) return;
        self.panic_mode = true;
        self.had_error = true;

        std.debug.print("[line {}:{}] Error", .{ token.line, token.column });

        if (token.type == .eof) {
            std.debug.print(" at end", .{});
        } else {
            std.debug.print(" at '{s}'", .{token.lexeme});
        }

        std.debug.print(": {s}\n", .{message});
    }

    fn synchronize(self: *Parser) void {
        self.panic_mode = false;

        while (self.current.type != .eof) {
            if (self.previous.type == .semicolon) return;

            switch (self.current.type) {
                .keyword_class,
                .keyword_union,
                .keyword_if,
                .keyword_while,
                .keyword_for,
                .keyword_return,
                => return,
                else => {},
            }

            self.advance() catch return;
        }
    }

    // ============================================================================
    // Declaration Parsing
    // ============================================================================

    /// Holds parsed declaration attributes
    const DeclAttributes = struct {
        func_attrs: ast.FunctionAttributes = .{},
        is_public: bool = false,
        is_static: bool = false,
        is_extern: bool = false,
    };

    /// Parse declaration attributes (public, static, extern, interrupt, etc.)
    fn parseAttributes(self: *Parser) ParserError!DeclAttributes {
        var attrs = DeclAttributes{};

        while (true) {
            if (try self.match(.keyword_public)) {
                attrs.is_public = true;
                attrs.func_attrs.is_public = true;
            } else if (try self.match(.keyword_static)) {
                attrs.is_static = true;
                attrs.func_attrs.is_static = true;
            } else if (try self.match(.keyword_extern) or try self.match(.keyword__extern)) {
                attrs.is_extern = true;
                attrs.func_attrs.is_extern = true;
            } else if (try self.match(.keyword_interrupt)) {
                attrs.func_attrs.is_interrupt = true;
            } else if (try self.match(.keyword_haserrcode)) {
                attrs.func_attrs.has_err_code = true;
            } else if (try self.match(.keyword_argpop)) {
                attrs.func_attrs.is_argpop = true;
            } else if (try self.match(.keyword_noargpop)) {
                attrs.func_attrs.is_noargpop = true;
            } else if (try self.match(.keyword_lock)) {
                attrs.func_attrs.is_lock = true;
            } else {
                break;
            }
        }

        return attrs;
    }

    fn parseDeclaration(self: *Parser) ParserError!Decl {
        // Parse declaration attributes
        const attrs = try self.parseAttributes();

        // Check for class/union declaration
        if (try self.match(.keyword_class)) {
            return try self.parseClassDeclaration(attrs.is_public, attrs.is_static, attrs.is_extern, null, null);
        }
        if (try self.match(.keyword_union)) {
            return try self.parseUnionDeclaration(attrs.is_public, attrs.is_static, attrs.is_extern, null, null);
        }

        // Try to parse type (for function/variable declaration)
        // This could be:
        // 1. Return type for function
        // 2. Type for global variable
        // 3. Representation type for class/union (e.g., "I64 class CDate")

        if (!self.isTypeStart()) {
            self.reportErrorAtCurrent("Expected declaration");
            return error.ParseError;
        }

        const decl_type = try self.parseType();

        // Check if this is a class/union with representation type
        if (try self.match(.keyword_class)) {
            return try self.parseClassDeclaration(attrs.is_public, attrs.is_static, attrs.is_extern, decl_type, null);
        }
        if (try self.match(.keyword_union)) {
            return try self.parseUnionDeclaration(attrs.is_public, attrs.is_static, attrs.is_extern, decl_type, null);
        }

        // Must be function or global variable - need identifier
        if (!self.check(.identifier)) {
            self.reportErrorAtCurrent("Expected identifier after type");
            return error.ParseError;
        }

        const name = self.current.lexeme;
        const name_loc = self.locationFromToken(self.current);
        try self.advance();

        // Check if this is a function (has parenthesis) or variable (has semicolon/assignment)
        if (try self.match(.lparen)) {
            // Function declaration
            const params = try self.parseParameterList();

            // Function body is optional (forward declaration)
            const body: ?Stmt = if (try self.match(.lbrace)) blk: {
                // We've consumed the '{', parseBlock expects it in previous
                break :blk try self.parseBlock();
            } else blk: {
                try self.consume(.semicolon, "Expected ';' or function body");
                break :blk null;
            };

            return Decl{
                .function = .{
                    .return_type = decl_type,
                    .name = name,
                    .params = params,
                    .body = body,
                    .attributes = attrs.func_attrs,
                    .loc = name_loc,
                },
            };
        } else {
            // Global variable declaration
            const init_expr: ?Expr = if (try self.match(.op_equal))
                try self.parseExpression()
            else
                null;

            try self.consume(.semicolon, "Expected ';' after variable declaration");

            return Decl{
                .global_var = .{
                    .type = decl_type,
                    .name = name,
                    .init = init_expr,
                    .loc = name_loc,
                },
            };
        }
    }

    /// Parse parameter list for function: (Type name, Type name, ...)
    fn parseParameterList(self: *Parser) ParserError![]ast.Param {
        const empty_slice = try self.ast_allocator.alloc(ast.Param, 0);
        var params = std.ArrayList(ast.Param).fromOwnedSlice(empty_slice);
        errdefer params.deinit(self.ast_allocator);

        // Empty parameter list
        if (try self.match(.rparen)) {
            return try params.toOwnedSlice(self.ast_allocator);
        }

        // Parse parameters
        while (true) {
            const param_type = try self.parseType();

            if (!self.check(.identifier)) {
                self.reportErrorAtCurrent("Expected parameter name");
                return error.ParseError;
            }

            const param_name = self.current.lexeme;
            const param_loc = self.locationFromToken(self.current);
            try self.advance();

            try params.append(self.ast_allocator, ast.Param{
                .type = param_type,
                .name = param_name,
                .loc = param_loc,
            });

            if (!try self.match(.comma)) {
                break;
            }
        }

        try self.consume(.rparen, "Expected ')' after parameter list");
        return try params.toOwnedSlice(self.ast_allocator);
    }

    /// Parse class or union members: Type name; Type name; ...
    fn parseMembers(self: *Parser) ParserError![]ast.ClassMember {
        const empty_slice = try self.ast_allocator.alloc(ast.ClassMember, 0);
        var members = std.ArrayList(ast.ClassMember).fromOwnedSlice(empty_slice);
        errdefer members.deinit(self.ast_allocator);

        while (!self.check(.rbrace) and !self.check(.eof)) {
            const member_type = try self.parseType();

            if (!self.check(.identifier)) {
                self.reportErrorAtCurrent("Expected member name");
                return error.ParseError;
            }

            const member_name = self.current.lexeme;
            const member_loc = self.locationFromToken(self.current);
            try self.advance();

            try self.consume(.semicolon, "Expected ';' after member declaration");

            try members.append(self.ast_allocator, ast.ClassMember{
                .type = member_type,
                .name = member_name,
                .loc = member_loc,
            });
        }

        return try members.toOwnedSlice(self.ast_allocator);
    }

    /// Parse class declaration
    /// Syntax: [visibility] [repr_type] [alias] class Name [: Base] { members }
    fn parseClassDeclaration(
        self: *Parser,
        is_public: bool,
        is_static: bool,
        is_extern: bool,
        repr_type: ?Type,
        alias: ?[]const u8,
    ) ParserError!Decl {
        // The alias parameter is passed when we've already seen "Type alias class"
        // If alias is null, we need to parse the class name
        // If alias is not null, the next identifier is the class name

        const class_alias = alias;
        var class_name: []const u8 = undefined;

        // Parse: [alias] class Name
        // OR: Name (if repr_type is provided)
        if (repr_type != null and alias == null) {
            // Syntax: "I64 class CDate" - next token is class name
            if (!self.check(.identifier)) {
                self.reportErrorAtCurrent("Expected class name");
                return error.ParseError;
            }
            class_name = self.current.lexeme;
        } else if (alias != null) {
            // Syntax: "I64 CDateAlias class CDate" - alias already parsed, get name
            if (!self.check(.identifier)) {
                self.reportErrorAtCurrent("Expected class name");
                return error.ParseError;
            }
            class_name = self.current.lexeme;
        } else {
            // Syntax: "class CDate" - next token is class name
            if (!self.check(.identifier)) {
                self.reportErrorAtCurrent("Expected class name");
                return error.ParseError;
            }
            class_name = self.current.lexeme;
        }

        const class_loc = self.locationFromToken(self.current);
        try self.advance();

        // Check for inheritance: class Derived : Base
        var base_class: ?[]const u8 = null;
        if (try self.match(.colon)) {
            if (!self.check(.identifier)) {
                self.reportErrorAtCurrent("Expected base class name");
                return error.ParseError;
            }
            base_class = self.current.lexeme;
            try self.advance();
        }

        // Parse class body
        try self.consume(.lbrace, "Expected '{' before class body");

        const members = try self.parseMembers();

        try self.consume(.rbrace, "Expected '}' after class body");
        try self.consume(.semicolon, "Expected ';' after class declaration");

        return Decl{
            .class = .{
                .name = class_name,
                .alias = class_alias,
                .repr_type = repr_type,
                .base_class = base_class,
                .is_public = is_public,
                .is_static = is_static,
                .is_extern = is_extern,
                .members = members,
                .loc = class_loc,
            },
        };
    }

    /// Parse union declaration
    /// Syntax: [visibility] [repr_type] [alias] union Name { members }
    fn parseUnionDeclaration(
        self: *Parser,
        is_public: bool,
        is_static: bool,
        is_extern: bool,
        repr_type: ?Type,
        alias: ?[]const u8,
    ) ParserError!Decl {
        // Same logic as class: alias is only used in special syntax like "U16i union U16"
        const union_alias = alias;
        var union_name: []const u8 = undefined;

        // Just parse the union name - it's always the next identifier
        if (!self.check(.identifier)) {
            self.reportErrorAtCurrent("Expected union name");
            return error.ParseError;
        }

        union_name = self.current.lexeme;
        const union_loc = self.locationFromToken(self.current);
        try self.advance();

        // Parse union body
        try self.consume(.lbrace, "Expected '{' before union body");

        const members = try self.parseMembers();

        try self.consume(.rbrace, "Expected '}' after union body");
        try self.consume(.semicolon, "Expected ';' after union declaration");

        return Decl{
            .union_decl = .{
                .name = union_name,
                .alias = union_alias,
                .repr_type = repr_type,
                .is_public = is_public,
                .is_static = is_static,
                .is_extern = is_extern,
                .members = members,
                .loc = union_loc,
            },
        };
    }

    // ============================================================================
    // Expression Parsing (Pratt Parser)
    // ============================================================================

    /// Parse an expression
    pub fn parseExpression(self: *Parser) ParserError!Expr {
        return self.parsePrecedence(PREC_LOWEST);
    }

    /// Parse expression with minimum precedence (Pratt parsing)
    fn parsePrecedence(self: *Parser, min_precedence: u8) ParserError!Expr {
        // Parse prefix expression (literals, identifiers, unary operators, grouping)
        var left = try self.parsePrefix();

        // Parse postfix and infix expressions
        while (true) {
            // Check for postfix operators (highest precedence)
            if (try self.parsePostfix(&left)) {
                continue; // Postfix consumed, check for more
            }

            // Check for binary operators
            const op = self.currentBinaryOp() orelse break;
            const precedence = op.precedence();

            if (precedence < min_precedence) break;

            try self.advance(); // Consume operator

            // For right-associative operators, use same precedence
            // For left-associative, use precedence + 1
            const next_min = if (op.isRightAssociative()) precedence else precedence + 1;

            const right = try self.parsePrecedence(next_min);

            // Create binary expression
            const left_ptr = try self.ast_allocator.create(Expr);
            left_ptr.* = left;

            const right_ptr = try self.ast_allocator.create(Expr);
            right_ptr.* = right;

            left = Expr{
                .binary = .{
                    .op = op,
                    .left = left_ptr,
                    .right = right_ptr,
                    .loc = self.locationFromToken(self.previous),
                },
            };
        }

        return left;
    }

    /// Parse prefix expression (primary, unary, grouping)
    fn parsePrefix(self: *Parser) ParserError!Expr {
        // sizeof expression: sizeof(expr) or sizeof(Type)
        if (try self.match(.keyword_sizeof)) {
            return try self.parseSizeofExpression();
        }

        // offset expression: offset(Type, member)
        if (try self.match(.keyword_offset)) {
            return try self.parseOffsetExpression();
        }

        // Unary operators
        if (try self.parseUnaryOperator()) |unary_op| {
            const op_token = self.previous;
            const operand = try self.parsePrecedence(PREC_UNARY);

            const operand_ptr = try self.ast_allocator.create(Expr);
            operand_ptr.* = operand;

            return Expr{
                .unary = .{
                    .op = unary_op,
                    .operand = operand_ptr,
                    .loc = self.locationFromToken(op_token),
                },
            };
        }

        // Grouping or Type cast: (expr) or (Type)expr
        if (try self.match(.lparen)) {
            // Look ahead to determine if this is a cast or grouping
            // Save state for potential backtrack
            const saved_current = self.current;
            const saved_previous = self.previous;

            // Try to parse as type
            const is_type = self.isTypeStart();

            if (is_type) {
                // Try parsing type for cast
                if (self.parseType()) |cast_type| {
                    if (try self.match(.rparen)) {
                        // It's a cast: (Type)expr
                        const cast_loc = self.locationFromToken(saved_previous);
                        const expr = try self.parsePrecedence(PREC_CAST);

                        const expr_ptr = try self.ast_allocator.create(Expr);
                        expr_ptr.* = expr;

                        return Expr{
                            .cast = .{
                                .type = cast_type,
                                .expr = expr_ptr,
                                .loc = cast_loc,
                            },
                        };
                    }
                } else |_| {
                    // Failed to parse as type, restore and parse as grouping
                    self.current = saved_current;
                    self.previous = saved_previous;
                }

                // If we got here and didn't return, restore state and parse as grouping
                if (self.current.type != saved_current.type) {
                    self.current = saved_current;
                    self.previous = saved_previous;
                }
            }

            // Parse as grouping expression
            const expr = try self.parseExpression();
            try self.consume(.rparen, "Expected ')' after expression");
            return expr;
        }

        // Primary expressions (literals, identifiers)
        return self.parsePrimary();
    }

    /// Parse primary expression (literals, identifiers)
    fn parsePrimary(self: *Parser) ParserError!Expr {
        _ = self.current;

        // Integer literal
        if (try self.match(.integer_literal)) {
            const value = try std.fmt.parseInt(i64, self.previous.lexeme, 0);
            return Expr{
                .integer = .{
                    .value = value,
                    .loc = self.locationFromToken(self.previous),
                },
            };
        }

        // Float literal
        if (try self.match(.float_literal)) {
            const value = try std.fmt.parseFloat(f64, self.previous.lexeme);
            return Expr{
                .float = .{
                    .value = value,
                    .loc = self.locationFromToken(self.previous),
                },
            };
        }

        // String literal
        if (try self.match(.string_literal)) {
            // Remove quotes from string
            const lexeme = self.previous.lexeme;
            const value = if (lexeme.len >= 2)
                lexeme[1 .. lexeme.len - 1]
            else
                lexeme;

            return Expr{
                .string = .{
                    .value = value,
                    .loc = self.locationFromToken(self.previous),
                },
            };
        }

        // Character literal
        if (try self.match(.char_literal)) {
            // Parse character literal (including multi-char constants)
            const lexeme = self.previous.lexeme;
            const chars = if (lexeme.len >= 2)
                lexeme[1 .. lexeme.len - 1]
            else
                lexeme;

            // Pack characters into u32 (HolyC multi-char constant)
            var value: u32 = 0;
            for (chars, 0..) |c, i| {
                if (i >= 4) break; // Max 4 chars
                value = (value << 8) | c;
            }

            return Expr{
                .char = .{
                    .value = value,
                    .loc = self.locationFromToken(self.previous),
                },
            };
        }

        // Identifier
        if (try self.match(.identifier)) {
            return Expr{
                .identifier = .{
                    .name = self.previous.lexeme,
                    .loc = self.locationFromToken(self.previous),
                },
            };
        }

        self.reportErrorAtCurrent("Expected expression");
        return error.ParseError;
    }

    /// Get current binary operator if present
    fn currentBinaryOp(self: *Parser) ?BinaryOp {
        return ops.tokenToBinaryOp(self.current.type);
    }

    /// Parse unary operator if present
    fn parseUnaryOperator(self: *Parser) ParserError!?UnaryOp {
        const op = ops.tokenToUnaryOp(self.current.type) orelse return null;
        try self.advance();
        return op;
    }

    /// Parse sizeof expression: sizeof(expr) or sizeof(Type)
    fn parseSizeofExpression(self: *Parser) ParserError!Expr {
        const sizeof_loc = self.locationFromToken(self.previous);

        try self.consume(.lparen, "Expected '(' after 'sizeof'");

        // Try to parse as type first
        if (self.isTypeStart()) {
            const saved_current = self.current;
            const saved_previous = self.previous;

            if (self.parseType()) |sizeof_type| {
                if (try self.match(.rparen)) {
                    return Expr{
                        .sizeof_type = .{
                            .type = sizeof_type,
                            .loc = sizeof_loc,
                        },
                    };
                }
            } else |_| {}

            // Restore state if type parsing failed
            self.current = saved_current;
            self.previous = saved_previous;
        }

        // Parse as expression
        const expr = try self.parseExpression();
        try self.consume(.rparen, "Expected ')' after sizeof expression");

        const expr_ptr = try self.ast_allocator.create(Expr);
        expr_ptr.* = expr;

        return Expr{
            .sizeof_expr = .{
                .expr = expr_ptr,
                .loc = sizeof_loc,
            },
        };
    }

    /// Parse offset expression: offset(Type, member)
    fn parseOffsetExpression(self: *Parser) ParserError!Expr {
        const offset_loc = self.locationFromToken(self.previous);

        try self.consume(.lparen, "Expected '(' after 'offset'");

        const offset_type = try self.parseType();

        try self.consume(.comma, "Expected ',' after type in offset");

        if (!self.check(.identifier)) {
            self.reportErrorAtCurrent("Expected member name in offset");
            return error.ParseError;
        }

        const member = self.current.lexeme;
        try self.advance();

        try self.consume(.rparen, "Expected ')' after offset expression");

        return Expr{
            .offset = .{
                .type = offset_type,
                .member = member,
                .loc = offset_loc,
            },
        };
    }

    /// Create source location from token
    fn locationFromToken(self: *Parser, token: Token) SourceLocation {
        _ = self;
        return SourceLocation{
            .line = token.line,
            .column = token.column,
        };
    }

    // ============================================================================
    // Type Parsing
    // ============================================================================

    /// Parse a type expression
    /// Handles: I64, U32*, I64[10], I64[], MyClass, etc.
    pub fn parseType(self: *Parser) ParserError!Type {
        // Parse base type (primitive or named)
        var base_type = try self.parseBaseType();

        // Handle pointer suffix: T* or T**
        while (try self.match(.op_star)) {
            const ptr_type = try self.ast_allocator.create(Type);
            ptr_type.* = base_type;
            base_type = Type{ .pointer = ptr_type };
        }

        // Handle array suffix: T[n] or T[]
        if (try self.match(.lbracket)) {
            const element_type_ptr = try self.ast_allocator.create(Type);
            element_type_ptr.* = base_type;

            // Check for array size
            const size: ?u64 = if (self.check(.rbracket))
                null // Unsized array: T[]
            else blk: {
                // Sized array: T[n]
                const size_expr = try self.parseExpression();
                // TODO: Evaluate constant expression for size
                // For now, just check if it's an integer literal
                if (size_expr != .integer) {
                    self.reportErrorAtCurrent("Array size must be a constant integer");
                    return error.ParseError;
                }
                break :blk @intCast(size_expr.integer.value);
            };

            try self.consume(.rbracket, "Expected ']' after array size");

            base_type = Type{
                .array = .{
                    .element_type = element_type_ptr,
                    .size = size,
                },
            };

            // Handle pointer suffix after array: T[n]* or T[]*
            while (try self.match(.op_star)) {
                const ptr_type = try self.ast_allocator.create(Type);
                ptr_type.* = base_type;
                base_type = Type{ .pointer = ptr_type };
            }
        }

        return base_type;
    }

    /// Parse base type (primitive or named type)
    fn parseBaseType(self: *Parser) ParserError!Type {
        // Primitive types
        if (try self.match(.keyword_i0)) return .i0;
        if (try self.match(.keyword_i8)) return .i8;
        if (try self.match(.keyword_i16)) return .i16;
        if (try self.match(.keyword_i32)) return .i32;
        if (try self.match(.keyword_i64)) return .i64;
        if (try self.match(.keyword_u0)) return .u0;
        if (try self.match(.keyword_u8)) return .u8;
        if (try self.match(.keyword_u16)) return .u16;
        if (try self.match(.keyword_u32)) return .u32;
        if (try self.match(.keyword_u64)) return .u64;
        if (try self.match(.keyword_f64)) return .f64;

        // Named type (class/union name)
        if (try self.match(.identifier)) {
            return Type{ .named = self.previous.lexeme };
        }

        self.reportErrorAtCurrent("Expected type name");
        return error.ParseError;
    }

    // ============================================================================
    // Statement Parsing
    // ============================================================================

    /// Parse a statement
    pub fn parseStatement(self: *Parser) ParserError!Stmt {
        // Block: { stmts }
        if (try self.match(.lbrace)) {
            return try self.parseBlock();
        }

        // If statement: if (cond) stmt [else stmt]
        if (try self.match(.keyword_if)) {
            return try self.parseIfStatement();
        }

        // While loop: while (cond) stmt
        if (try self.match(.keyword_while)) {
            return try self.parseWhileStatement();
        }

        // Do-while loop: do stmt while (cond);
        if (try self.match(.keyword_do)) {
            return try self.parseDoWhileStatement();
        }

        // For loop: for (init; cond; incr) stmt
        if (try self.match(.keyword_for)) {
            return try self.parseForStatement();
        }

        // Return statement: return [expr];
        if (try self.match(.keyword_return)) {
            return try self.parseReturnStatement();
        }

        // Break statement: break;
        if (try self.match(.keyword_break)) {
            const loc = self.locationFromToken(self.previous);
            try self.consume(.semicolon, "Expected ';' after 'break'");
            return Stmt{ .break_stmt = .{ .loc = loc } };
        }

        // Switch statement: switch (expr) { case val: ... }
        if (try self.match(.keyword_switch)) {
            return try self.parseSwitchStatement();
        }

        // Goto statement: goto label;
        if (try self.match(.keyword_goto)) {
            return try self.parseGotoStatement();
        }

        // Try-catch: try { } catch { }
        if (try self.match(.keyword_try)) {
            return try self.parseTryCatchStatement();
        }

        // TODO: Handle labels (identifier:) - requires lexer lookahead
        // For now, labels will be parsed as expression statements and caught in semantic analysis

        // Variable declaration: Type name = expr;
        // We need to distinguish between declarations and expressions
        // If current token is a type keyword, it's a declaration
        if (self.isTypeStart()) {
            return try self.parseVarDeclaration();
        }

        // Expression statement: expr;
        return try self.parseExpressionStatement();
    }

    /// Check if current token can start a type
    fn isTypeStart(self: *Parser) bool {
        return ops.isTypeStartToken(self.current.type);
    }

    /// Parse variable declaration: Type name = expr;
    fn parseVarDeclaration(self: *Parser) ParserError!Stmt {
        const decl_loc = self.locationFromToken(self.current);

        // Parse type
        const var_type = try self.parseType();

        // Parse variable name
        try self.consume(.identifier, "Expected variable name");
        const var_name = self.previous.lexeme;

        // Optional initializer
        const init_expr: ?Expr = if (try self.match(.op_equal))
            try self.parseExpression()
        else
            null;

        // Expect semicolon
        try self.consume(.semicolon, "Expected ';' after variable declaration");

        return Stmt{
            .var_decl = .{
                .type = var_type,
                .name = var_name,
                .init = init_expr,
                .loc = decl_loc,
            },
        };
    }

    /// Parse expression statement: expr;
    fn parseExpressionStatement(self: *Parser) ParserError!Stmt {
        const stmt_loc = self.locationFromToken(self.current);
        const expr = try self.parseExpression();
        try self.consume(.semicolon, "Expected ';' after expression");

        return Stmt{
            .expr = .{
                .expr = expr,
                .loc = stmt_loc,
            },
        };
    }

    /// Parse block statement: { stmts }
    fn parseBlock(self: *Parser) ParserError!Stmt {
        const block_loc = self.locationFromToken(self.previous);
        const empty_slice = try self.ast_allocator.alloc(Stmt, 0);
        var stmts = std.ArrayList(Stmt).fromOwnedSlice(empty_slice);
        errdefer stmts.deinit(self.ast_allocator);

        while (!self.check(.rbrace) and !self.check(.eof)) {
            const stmt = try self.parseStatement();
            try stmts.append(self.ast_allocator, stmt);
        }

        try self.consume(.rbrace, "Expected '}' after block");

        return Stmt{
            .block = .{
                .stmts = try stmts.toOwnedSlice(self.ast_allocator),
                .loc = block_loc,
            },
        };
    }

    /// Parse if statement: if (cond) stmt [else stmt]
    fn parseIfStatement(self: *Parser) ParserError!Stmt {
        const if_loc = self.locationFromToken(self.previous);

        try self.consume(.lparen, "Expected '(' after 'if'");
        const condition = try self.parseExpression();
        try self.consume(.rparen, "Expected ')' after if condition");

        const then_stmt_ptr = try self.ast_allocator.create(Stmt);
        then_stmt_ptr.* = try self.parseStatement();

        const else_stmt_ptr: ?*Stmt = if (try self.match(.keyword_else)) blk: {
            const ptr = try self.ast_allocator.create(Stmt);
            ptr.* = try self.parseStatement();
            break :blk ptr;
        } else null;

        return Stmt{
            .if_stmt = .{
                .condition = condition,
                .then_stmt = then_stmt_ptr,
                .else_stmt = else_stmt_ptr,
                .loc = if_loc,
            },
        };
    }

    /// Parse while statement: while (cond) stmt
    fn parseWhileStatement(self: *Parser) ParserError!Stmt {
        const while_loc = self.locationFromToken(self.previous);

        try self.consume(.lparen, "Expected '(' after 'while'");
        const condition = try self.parseExpression();
        try self.consume(.rparen, "Expected ')' after while condition");

        const body_ptr = try self.ast_allocator.create(Stmt);
        body_ptr.* = try self.parseStatement();

        return Stmt{
            .while_stmt = .{
                .condition = condition,
                .body = body_ptr,
                .loc = while_loc,
            },
        };
    }

    /// Parse do-while statement: do stmt while (cond);
    fn parseDoWhileStatement(self: *Parser) ParserError!Stmt {
        const do_loc = self.locationFromToken(self.previous);

        const body_ptr = try self.ast_allocator.create(Stmt);
        body_ptr.* = try self.parseStatement();

        try self.consume(.keyword_while, "Expected 'while' after do-while body");
        try self.consume(.lparen, "Expected '(' after 'while'");
        const condition = try self.parseExpression();
        try self.consume(.rparen, "Expected ')' after while condition");
        try self.consume(.semicolon, "Expected ';' after do-while statement");

        return Stmt{
            .do_while = .{
                .body = body_ptr,
                .condition = condition,
                .loc = do_loc,
            },
        };
    }

    /// Parse for statement: for (init; cond; incr) stmt
    fn parseForStatement(self: *Parser) ParserError!Stmt {
        const for_loc = self.locationFromToken(self.previous);

        try self.consume(.lparen, "Expected '(' after 'for'");

        // Parse initializer (can be declaration or expression)
        const init_stmt: ?*Stmt = if (try self.match(.semicolon))
            null // No initializer
        else blk: {
            const ptr = try self.ast_allocator.create(Stmt);
            ptr.* = try self.parseStatement();
            break :blk ptr;
        };

        // Parse condition
        const condition: ?Expr = if (self.check(.semicolon))
            null // No condition
        else
            try self.parseExpression();
        try self.consume(.semicolon, "Expected ';' after for condition");

        // Parse increment
        const increment: ?Expr = if (self.check(.rparen))
            null // No increment
        else
            try self.parseExpression();
        try self.consume(.rparen, "Expected ')' after for clauses");

        // Parse body
        const body_ptr = try self.ast_allocator.create(Stmt);
        body_ptr.* = try self.parseStatement();

        return Stmt{
            .for_stmt = .{
                .init = init_stmt,
                .condition = condition,
                .increment = increment,
                .body = body_ptr,
                .loc = for_loc,
            },
        };
    }

    /// Parse return statement: return [expr];
    fn parseReturnStatement(self: *Parser) ParserError!Stmt {
        const return_loc = self.locationFromToken(self.previous);

        const expr: ?Expr = if (self.check(.semicolon))
            null
        else
            try self.parseExpression();

        try self.consume(.semicolon, "Expected ';' after return statement");

        return Stmt{
            .return_stmt = .{
                .expr = expr,
                .loc = return_loc,
            },
        };
    }

    /// Parse switch statement: switch (expr) { case val: stmts... default: stmts... }
    fn parseSwitchStatement(self: *Parser) ParserError!Stmt {
        const switch_loc = self.locationFromToken(self.previous);

        try self.consume(.lparen, "Expected '(' after 'switch'");
        const switch_expr = try self.parseExpression();
        try self.consume(.rparen, "Expected ')' after switch expression");
        try self.consume(.lbrace, "Expected '{' before switch body");

        const empty_slice = try self.ast_allocator.alloc(ast.SwitchCase, 0);
        var cases = std.ArrayList(ast.SwitchCase).fromOwnedSlice(empty_slice);
        errdefer cases.deinit(self.ast_allocator);

        while (!self.check(.rbrace) and !self.check(.eof)) {
            if (try self.match(.keyword_case)) {
                // Parse case value
                const case_value = try self.parseExpression();
                try self.consume(.colon, "Expected ':' after case value");

                // Parse statements until next case/default/}
                const empty_stmts = try self.ast_allocator.alloc(Stmt, 0);
                var stmts = std.ArrayList(Stmt).fromOwnedSlice(empty_stmts);
                errdefer stmts.deinit(self.ast_allocator);

                while (!self.check(.keyword_case) and !self.check(.keyword_default) and !self.check(.rbrace)) {
                    const stmt = try self.parseStatement();
                    try stmts.append(self.ast_allocator, stmt);
                }

                try cases.append(self.ast_allocator, ast.SwitchCase{
                    .value = case_value,
                    .stmts = try stmts.toOwnedSlice(self.ast_allocator),
                    .loc = self.locationFromToken(self.previous),
                });
            } else if (try self.match(.keyword_default)) {
                try self.consume(.colon, "Expected ':' after 'default'");

                // Parse default statements
                const empty_stmts = try self.ast_allocator.alloc(Stmt, 0);
                var stmts = std.ArrayList(Stmt).fromOwnedSlice(empty_stmts);
                errdefer stmts.deinit(self.ast_allocator);

                while (!self.check(.keyword_case) and !self.check(.rbrace)) {
                    const stmt = try self.parseStatement();
                    try stmts.append(self.ast_allocator, stmt);
                }

                // Default case uses null value
                try cases.append(self.ast_allocator, ast.SwitchCase{
                    .value = null,
                    .stmts = try stmts.toOwnedSlice(self.ast_allocator),
                    .loc = self.locationFromToken(self.previous),
                });
            } else {
                self.reportErrorAtCurrent("Expected 'case' or 'default' in switch body");
                return error.ParseError;
            }
        }

        try self.consume(.rbrace, "Expected '}' after switch body");

        return Stmt{
            .switch_stmt = .{
                .expr = switch_expr,
                .cases = try cases.toOwnedSlice(self.ast_allocator),
                .loc = switch_loc,
            },
        };
    }

    /// Parse goto statement: goto label;
    fn parseGotoStatement(self: *Parser) ParserError!Stmt {
        const goto_loc = self.locationFromToken(self.previous);

        if (!self.check(.identifier)) {
            self.reportErrorAtCurrent("Expected label name after 'goto'");
            return error.ParseError;
        }

        const label = self.current.lexeme;
        try self.advance();

        try self.consume(.semicolon, "Expected ';' after goto statement");

        return Stmt{
            .goto_stmt = .{
                .label = label,
                .loc = goto_loc,
            },
        };
    }

    /// Parse try-catch statement: try { } catch { }
    fn parseTryCatchStatement(self: *Parser) ParserError!Stmt {
        const try_loc = self.locationFromToken(self.previous);

        // Parse try block
        try self.consume(.lbrace, "Expected '{' after 'try'");
        const try_block_ptr = try self.ast_allocator.create(Stmt);
        try_block_ptr.* = try self.parseBlock();

        // Parse catch block
        try self.consume(.keyword_catch, "Expected 'catch' after try block");
        try self.consume(.lbrace, "Expected '{' after 'catch'");
        const catch_block_ptr = try self.ast_allocator.create(Stmt);
        catch_block_ptr.* = try self.parseBlock();

        return Stmt{
            .try_catch = .{
                .try_block = try_block_ptr,
                .catch_block = catch_block_ptr,
                .loc = try_loc,
            },
        };
    }

    // ============================================================================
    // Type Parsing
    // ============================================================================
    // Postfix Operator Parsing
    // ============================================================================

    /// Parse postfix operators (function call, array subscript, member access, etc.)
    /// Returns true if a postfix operator was consumed and the left expression was modified
    fn parsePostfix(self: *Parser, left: *Expr) ParserError!bool {
        // Function call: func(args)
        if (try self.match(.lparen)) {
            const args = try self.parseCallArguments();
            const left_ptr = try self.ast_allocator.create(Expr);
            left_ptr.* = left.*;
            left.* = Expr{
                .call = .{
                    .callee = left_ptr,
                    .args = args,
                    .loc = self.locationFromToken(self.previous),
                },
            };
            return true;
        }

        // Array subscript: arr[index]
        if (try self.match(.lbracket)) {
            const index = try self.parseExpression();
            try self.consume(.rbracket, "Expected ']' after array subscript");
            const array_ptr = try self.ast_allocator.create(Expr);
            array_ptr.* = left.*;
            const index_ptr = try self.ast_allocator.create(Expr);
            index_ptr.* = index;
            left.* = Expr{
                .subscript = .{
                    .array = array_ptr,
                    .index = index_ptr,
                    .loc = self.locationFromToken(self.previous),
                },
            };
            return true;
        }

        // Member access: obj.member
        if (try self.match(.op_dot)) {
            try self.consume(.identifier, "Expected member name after '.'");
            const member_name = self.previous.lexeme;
            const object_ptr = try self.ast_allocator.create(Expr);
            object_ptr.* = left.*;
            left.* = Expr{
                .member = .{
                    .object = object_ptr,
                    .member = member_name,
                    .loc = self.locationFromToken(self.previous),
                },
            };
            return true;
        }

        // Arrow operator: ptr->member
        if (try self.match(.op_arrow)) {
            try self.consume(.identifier, "Expected member name after '->'");
            const member_name = self.previous.lexeme;
            const object_ptr = try self.ast_allocator.create(Expr);
            object_ptr.* = left.*;
            left.* = Expr{
                .arrow = .{
                    .object = object_ptr,
                    .member = member_name,
                    .loc = self.locationFromToken(self.previous),
                },
            };
            return true;
        }

        // Postfix increment: x++
        if (try self.match(.op_plus_plus)) {
            const operand_ptr = try self.ast_allocator.create(Expr);
            operand_ptr.* = left.*;
            left.* = Expr{
                .unary = .{
                    .op = .post_increment,
                    .operand = operand_ptr,
                    .loc = self.locationFromToken(self.previous),
                },
            };
            return true;
        }

        // Postfix decrement: x--
        if (try self.match(.op_minus_minus)) {
            const operand_ptr = try self.ast_allocator.create(Expr);
            operand_ptr.* = left.*;
            left.* = Expr{
                .unary = .{
                    .op = .post_decrement,
                    .operand = operand_ptr,
                    .loc = self.locationFromToken(self.previous),
                },
            };
            return true;
        }

        return false; // No postfix operator found
    }

    /// Parse function call arguments: (arg1, arg2, ...)
    /// Assumes '(' has already been consumed
    fn parseCallArguments(self: *Parser) ParserError![]Expr {
        const empty_slice = try self.ast_allocator.alloc(Expr, 0);
        var args_list = std.ArrayList(Expr).fromOwnedSlice(empty_slice);
        errdefer args_list.deinit(self.ast_allocator);

        // Empty argument list: ()
        if (self.check(.rparen)) {
            try self.advance();
            return args_list.toOwnedSlice(self.ast_allocator);
        }

        // Parse arguments
        while (true) {
            const arg = try self.parseExpression();
            try args_list.append(self.ast_allocator, arg);

            if (!try self.match(.comma)) break;
        }

        try self.consume(.rparen, "Expected ')' after function arguments");
        return args_list.toOwnedSlice(self.ast_allocator);
    }
};

// Import tests
test {
    _ = @import("parser_test.zig");
}
