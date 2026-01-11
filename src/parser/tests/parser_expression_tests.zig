//! Basic expression parsing tests: literals, binary/unary operators, precedence
const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const lexer = @import("../../lexer/lexer.zig");
const Lexer = lexer.Lexer;
const ast = @import("../ast.zig");

const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Type = ast.Type;

test "Parser initialization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "42";
    var lex = Lexer.init(allocator, source);
    const parser = try Parser.init(allocator, &lex);

    try testing.expectEqual(lexer.TokenType.integer_literal, parser.current.type);
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
