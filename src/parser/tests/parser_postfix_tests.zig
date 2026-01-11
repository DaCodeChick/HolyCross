//! Postfix operator tests: function calls, array subscripts, member access
const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const lexer = @import("../../lexer/lexer.zig");
const Lexer = lexer.Lexer;
const ast = @import("../ast.zig");

const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Type = ast.Type;

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
