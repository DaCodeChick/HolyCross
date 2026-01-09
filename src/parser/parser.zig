const std = @import("std");
const lexer = @import("../lexer/lexer.zig");
const ast = @import("ast.zig");

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
        const empty_slice = try self.allocator.alloc(Decl, 0);
        var decls = std.ArrayList(Decl).fromOwnedSlice(empty_slice);
        errdefer decls.deinit(self.allocator);

        while (!self.check(.eof)) {
            if (self.parseDeclaration()) |decl| {
                try decls.append(self.allocator, decl);
            } else |err| {
                if (err == error.ParseError) {
                    self.synchronize();
                } else {
                    return err;
                }
            }
        }

        return Program{
            .decls = try decls.toOwnedSlice(self.allocator),
            .allocator = self.allocator,
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

    fn parseDeclaration(self: *Parser) ParserError!Decl {
        // For now, just parse expressions as statements
        // TODO: Implement proper declaration parsing
        const expr = try self.parseExpression();
        try self.consume(.semicolon, "Expected ';' after expression");

        // Wrap expression in a statement-like structure
        // This is temporary until we implement full declaration parsing
        _ = expr;
        return error.ParseError; // Placeholder
    }

    // ============================================================================
    // Expression Parsing (Pratt Parser)
    // ============================================================================

    /// Parse an expression
    pub fn parseExpression(self: *Parser) ParserError!Expr {
        return self.parsePrecedence(1); // Lowest precedence
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
            const left_ptr = try self.allocator.create(Expr);
            left_ptr.* = left;

            const right_ptr = try self.allocator.create(Expr);
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
        // Unary operators
        if (try self.parseUnaryOperator()) |unary_op| {
            const op_token = self.previous;
            const operand = try self.parsePrecedence(14); // High precedence for unary

            const operand_ptr = try self.allocator.create(Expr);
            operand_ptr.* = operand;

            return Expr{
                .unary = .{
                    .op = unary_op,
                    .operand = operand_ptr,
                    .loc = self.locationFromToken(op_token),
                },
            };
        }

        // Grouping: (expr)
        if (try self.match(.lparen)) {
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
        return switch (self.current.type) {
            .op_plus => .add,
            .op_minus => .subtract,
            .op_star => .multiply,
            .op_slash => .divide,
            .op_percent => .modulo,
            .op_ampersand => .bitwise_and,
            .op_pipe => .bitwise_or,
            .op_caret => .bitwise_xor,
            .op_less_less => .shift_left,
            .op_greater_greater => .shift_right,
            .op_ampersand_ampersand => .logical_and,
            .op_pipe_pipe => .logical_or,
            .op_caret_caret => .logical_xor,
            .op_equal_equal => .equal,
            .op_not_equal => .not_equal,
            .op_less => .less,
            .op_less_equal => .less_equal,
            .op_greater => .greater,
            .op_greater_equal => .greater_equal,
            .op_equal => .assign,
            .op_plus_equal => .add_assign,
            .op_minus_equal => .sub_assign,
            .op_star_equal => .mul_assign,
            .op_slash_equal => .div_assign,
            .op_percent_equal => .mod_assign,
            .op_ampersand_equal => .and_assign,
            .op_pipe_equal => .or_assign,
            .op_caret_equal => .xor_assign,
            .op_less_less_equal => .shl_assign,
            .op_greater_greater_equal => .shr_assign,
            .op_backtick => .power,
            else => null,
        };
    }

    /// Parse unary operator if present
    fn parseUnaryOperator(self: *Parser) ParserError!?UnaryOp {
        if (try self.match(.op_minus)) return .negate;
        if (try self.match(.op_plus)) return .plus;
        if (try self.match(.op_exclamation)) return .logical_not;
        if (try self.match(.op_tilde)) return .bitwise_not;
        if (try self.match(.op_star)) return .dereference;
        if (try self.match(.op_ampersand)) return .address_of;
        if (try self.match(.op_plus_plus)) return .pre_increment;
        if (try self.match(.op_minus_minus)) return .pre_decrement;
        return null;
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
    // Postfix Operator Parsing
    // ============================================================================

    /// Parse postfix operators (function call, array subscript, member access, etc.)
    /// Returns true if a postfix operator was consumed and the left expression was modified
    fn parsePostfix(self: *Parser, left: *Expr) ParserError!bool {
        // Function call: func(args)
        if (try self.match(.lparen)) {
            const args = try self.parseCallArguments();
            const left_ptr = try self.allocator.create(Expr);
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
            const array_ptr = try self.allocator.create(Expr);
            array_ptr.* = left.*;
            const index_ptr = try self.allocator.create(Expr);
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
            const object_ptr = try self.allocator.create(Expr);
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
            const object_ptr = try self.allocator.create(Expr);
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
            const operand_ptr = try self.allocator.create(Expr);
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
            const operand_ptr = try self.allocator.create(Expr);
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
        const empty_slice = try self.allocator.alloc(Expr, 0);
        var args_list = std.ArrayList(Expr).fromOwnedSlice(empty_slice);
        errdefer args_list.deinit(self.allocator);

        // Empty argument list: ()
        if (self.check(.rparen)) {
            try self.advance();
            return args_list.toOwnedSlice(self.allocator);
        }

        // Parse arguments
        while (true) {
            const arg = try self.parseExpression();
            try args_list.append(self.allocator, arg);

            if (!try self.match(.comma)) break;
        }

        try self.consume(.rparen, "Expected ')' after function arguments");
        return args_list.toOwnedSlice(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Parser initialization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "42";
    var lex = Lexer.init(allocator, source);
    const parser = try Parser.init(allocator, &lex);

    try testing.expectEqual(TokenType.integer_literal, parser.current.type);
}

test "Parse integer literal" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "42";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqual(@as(i64, 42), expr.integer.value);
}

test "Parse float literal" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "3.14";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectApproxEqAbs(@as(f64, 3.14), expr.float.value, 0.0001);
}

test "Parse string literal" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "\"hello\"";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqualStrings("hello", expr.string.value);
}

test "Parse identifier" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "my_var";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqualStrings("my_var", expr.identifier.name);
}

test "Parse binary addition" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "1 + 2";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqual(BinaryOp.add, expr.binary.op);
    try testing.expectEqual(@as(i64, 1), expr.binary.left.integer.value);
    try testing.expectEqual(@as(i64, 2), expr.binary.right.integer.value);
}

test "Parse binary multiplication" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "3 * 4";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqual(BinaryOp.multiply, expr.binary.op);
    try testing.expectEqual(@as(i64, 3), expr.binary.left.integer.value);
    try testing.expectEqual(@as(i64, 4), expr.binary.right.integer.value);
}

test "Parse with correct precedence: 1 + 2 * 3" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Should parse as: 1 + (2 * 3)
    const source = "1 + 2 * 3";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root should be addition
    try testing.expectEqual(BinaryOp.add, expr.binary.op);
    try testing.expectEqual(@as(i64, 1), expr.binary.left.integer.value);

    // Right side should be multiplication
    try testing.expectEqual(BinaryOp.multiply, expr.binary.right.binary.op);
    try testing.expectEqual(@as(i64, 2), expr.binary.right.binary.left.integer.value);
    try testing.expectEqual(@as(i64, 3), expr.binary.right.binary.right.integer.value);
}

test "Parse with correct precedence: 2 * 3 + 4" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Should parse as: (2 * 3) + 4
    const source = "2 * 3 + 4";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root should be addition
    try testing.expectEqual(BinaryOp.add, expr.binary.op);
    try testing.expectEqual(@as(i64, 4), expr.binary.right.integer.value);

    // Left side should be multiplication
    try testing.expectEqual(BinaryOp.multiply, expr.binary.left.binary.op);
    try testing.expectEqual(@as(i64, 2), expr.binary.left.binary.left.integer.value);
    try testing.expectEqual(@as(i64, 3), expr.binary.left.binary.right.integer.value);
}

test "Parse parenthesized expression: (1 + 2) * 3" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "(1 + 2) * 3";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root should be multiplication
    try testing.expectEqual(BinaryOp.multiply, expr.binary.op);
    try testing.expectEqual(@as(i64, 3), expr.binary.right.integer.value);

    // Left side should be addition
    try testing.expectEqual(BinaryOp.add, expr.binary.left.binary.op);
    try testing.expectEqual(@as(i64, 1), expr.binary.left.binary.left.integer.value);
    try testing.expectEqual(@as(i64, 2), expr.binary.left.binary.right.integer.value);
}

test "Parse unary negation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "-42";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqual(UnaryOp.negate, expr.unary.op);
    try testing.expectEqual(@as(i64, 42), expr.unary.operand.integer.value);
}

test "Parse power operator: 2`8" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "2`8";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqual(BinaryOp.power, expr.binary.op);
    try testing.expectEqual(@as(i64, 2), expr.binary.left.integer.value);
    try testing.expectEqual(@as(i64, 8), expr.binary.right.integer.value);
}

test "Parse HolyC logical XOR: a ^^ b" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "a ^^ b";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expectEqual(BinaryOp.logical_xor, expr.binary.op);
    try testing.expectEqualStrings("a", expr.binary.left.identifier.name);
    try testing.expectEqualStrings("b", expr.binary.right.identifier.name);
}

test "Parse complex expression: -a + b * c" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "-a + b * c";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root: addition
    try testing.expectEqual(BinaryOp.add, expr.binary.op);

    // Left: unary negation of 'a'
    try testing.expectEqual(UnaryOp.negate, expr.binary.left.unary.op);
    try testing.expectEqualStrings("a", expr.binary.left.unary.operand.identifier.name);

    // Right: multiplication of 'b' and 'c'
    try testing.expectEqual(BinaryOp.multiply, expr.binary.right.binary.op);
    try testing.expectEqualStrings("b", expr.binary.right.binary.left.identifier.name);
    try testing.expectEqualStrings("c", expr.binary.right.binary.right.identifier.name);
}

// ============================================================================
// Postfix Operator Tests
// ============================================================================

test "Parse function call with no arguments" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "func()";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Should be a call expression
    try testing.expectEqualStrings("func", expr.call.callee.identifier.name);
    try testing.expectEqual(@as(usize, 0), expr.call.args.len);
}

test "Parse function call with single argument" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "func(42)";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqualStrings("func", expr.call.callee.identifier.name);
    try testing.expectEqual(@as(usize, 1), expr.call.args.len);
    try testing.expectEqual(@as(i64, 42), expr.call.args[0].integer.value);
}

test "Parse function call with multiple arguments" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "func(1, 2, 3)";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqualStrings("func", expr.call.callee.identifier.name);
    try testing.expectEqual(@as(usize, 3), expr.call.args.len);
    try testing.expectEqual(@as(i64, 1), expr.call.args[0].integer.value);
    try testing.expectEqual(@as(i64, 2), expr.call.args[1].integer.value);
    try testing.expectEqual(@as(i64, 3), expr.call.args[2].integer.value);
}

test "Parse array subscript" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "arr[0]";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqualStrings("arr", expr.subscript.array.identifier.name);
    try testing.expectEqual(@as(i64, 0), expr.subscript.index.integer.value);
}

test "Parse multi-dimensional array subscript" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "matrix[i][j]";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root: second subscript [j]
    try testing.expectEqualStrings("j", expr.subscript.index.identifier.name);

    // Left: first subscript matrix[i]
    try testing.expectEqualStrings("i", expr.subscript.array.subscript.index.identifier.name);
    try testing.expectEqualStrings("matrix", expr.subscript.array.subscript.array.identifier.name);
}

test "Parse member access" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "obj.field";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqualStrings("obj", expr.member.object.identifier.name);
    try testing.expectEqualStrings("field", expr.member.member);
}

test "Parse chained member access" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "obj.inner.field";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root: .field
    try testing.expectEqualStrings("field", expr.member.member);

    // Left: obj.inner
    try testing.expectEqualStrings("inner", expr.member.object.member.member);
    try testing.expectEqualStrings("obj", expr.member.object.member.object.identifier.name);
}

test "Parse arrow operator" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "ptr->field";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqualStrings("ptr", expr.arrow.object.identifier.name);
    try testing.expectEqualStrings("field", expr.arrow.member);
}

test "Parse postfix increment" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "x++";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqual(UnaryOp.post_increment, expr.unary.op);
    try testing.expectEqualStrings("x", expr.unary.operand.identifier.name);
}

test "Parse postfix decrement" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "x--";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqual(UnaryOp.post_decrement, expr.unary.op);
    try testing.expectEqualStrings("x", expr.unary.operand.identifier.name);
}

test "Parse complex postfix expression: obj.array[i].method()" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "obj.array[i].method()";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root: function call to method()
    try testing.expectEqual(@as(usize, 0), expr.call.args.len);

    // Callee: .method (member access)
    try testing.expectEqualStrings("method", expr.call.callee.member.member);

    // Object: obj.array[i] (subscript of member)
    try testing.expectEqualStrings("i", expr.call.callee.member.object.subscript.index.identifier.name);
    try testing.expectEqualStrings("array", expr.call.callee.member.object.subscript.array.member.member);
    try testing.expectEqualStrings("obj", expr.call.callee.member.object.subscript.array.member.object.identifier.name);
}

test "Parse mixed prefix and postfix: ++x--" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "++x--";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    // Root: prefix increment (prefix operators are parsed first)
    try testing.expectEqual(UnaryOp.pre_increment, expr.unary.op);

    // Operand: postfix decrement on x
    try testing.expectEqual(UnaryOp.post_decrement, expr.unary.operand.unary.op);
    try testing.expectEqualStrings("x", expr.unary.operand.unary.operand.identifier.name);
}

test "Parse array subscript with expression: arr[i + 1]" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "arr[i + 1]";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();

    try testing.expectEqualStrings("arr", expr.subscript.array.identifier.name);
    try testing.expectEqual(BinaryOp.add, expr.subscript.index.binary.op);
    try testing.expectEqualStrings("i", expr.subscript.index.binary.left.identifier.name);
    try testing.expectEqual(@as(i64, 1), expr.subscript.index.binary.right.integer.value);
}
