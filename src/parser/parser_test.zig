const std = @import("std");
const Parser = @import("parser.zig").Parser;
const lexer = @import("../lexer/lexer.zig");
const Lexer = lexer.Lexer;
const ast = @import("ast.zig");

const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Type = ast.Type;

// ============================================================================
// Parser Tests
// ============================================================================

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

// ============================================================================
// Type Parsing Tests
// ============================================================================

test "Parse primitive type: I64" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expectEqual(Type.i64, type_result);
}

test "Parse primitive type: U32" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "U32";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expectEqual(Type.u32, type_result);
}

test "Parse primitive type: F64" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "F64";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expectEqual(Type.f64, type_result);
}

test "Parse pointer type: I64*" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64*";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .pointer);
    try testing.expectEqual(Type.i64, type_result.pointer.*);
}

test "Parse double pointer type: U8**" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "U8**";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .pointer);
    try testing.expect(type_result.pointer.* == .pointer);
    try testing.expectEqual(Type.u8, type_result.pointer.pointer.*);
}

test "Parse sized array type: I64[10]" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64[10]";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .array);
    try testing.expectEqual(Type.i64, type_result.array.element_type.*);
    try testing.expectEqual(@as(u64, 10), type_result.array.size.?);
}

test "Parse unsized array type: U8[]" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "U8[]";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .array);
    try testing.expectEqual(Type.u8, type_result.array.element_type.*);
    try testing.expect(type_result.array.size == null);
}

test "Parse named type: MyClass" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "MyClass";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .named);
    try testing.expectEqualStrings("MyClass", type_result.named);
}

test "Parse pointer to named type: MyClass*" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "MyClass*";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .pointer);
    try testing.expect(type_result.pointer.* == .named);
    try testing.expectEqualStrings("MyClass", type_result.pointer.named);
}

test "Parse array of pointers: I64*[5]" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64*[5]";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .array);
    try testing.expectEqual(@as(u64, 5), type_result.array.size.?);
    try testing.expect(type_result.array.element_type.* == .pointer);
    try testing.expectEqual(Type.i64, type_result.array.element_type.pointer.*);
}

test "Parse pointer to array: I64[10]*" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64[10]*";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const type_result = try parser.parseType();
    try testing.expect(type_result == .pointer);
    try testing.expect(type_result.pointer.* == .array);
    try testing.expectEqual(@as(u64, 10), type_result.pointer.array.size.?);
    try testing.expectEqual(Type.i64, type_result.pointer.array.element_type.*);
}

// ============================================================================
// Statement Parsing Tests
// ============================================================================

test "Parse variable declaration: I64 x;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64 x;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .var_decl);
    try testing.expectEqual(Type.i64, stmt.var_decl.type);
    try testing.expectEqualStrings("x", stmt.var_decl.name);
    try testing.expect(stmt.var_decl.init == null);
}

test "Parse variable declaration with initializer: I64 x = 42;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64 x = 42;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .var_decl);
    try testing.expectEqual(Type.i64, stmt.var_decl.type);
    try testing.expectEqualStrings("x", stmt.var_decl.name);
    try testing.expect(stmt.var_decl.init != null);
    try testing.expectEqual(@as(i64, 42), stmt.var_decl.init.?.integer.value);
}

test "Parse variable declaration with expression: U32 y = a + b;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "U32 y = a + b;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .var_decl);
    try testing.expectEqual(Type.u32, stmt.var_decl.type);
    try testing.expectEqualStrings("y", stmt.var_decl.name);
    try testing.expect(stmt.var_decl.init != null);
    try testing.expect(stmt.var_decl.init.? == .binary);
    try testing.expectEqual(BinaryOp.add, stmt.var_decl.init.?.binary.op);
}

test "Parse pointer variable declaration: I64* ptr = &x;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64* ptr = &x;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .var_decl);
    try testing.expect(stmt.var_decl.type == .pointer);
    try testing.expectEqual(Type.i64, stmt.var_decl.type.pointer.*);
    try testing.expectEqualStrings("ptr", stmt.var_decl.name);
    try testing.expect(stmt.var_decl.init != null);
    try testing.expect(stmt.var_decl.init.? == .unary);
    try testing.expectEqual(UnaryOp.address_of, stmt.var_decl.init.?.unary.op);
}

test "Parse array variable declaration: I64[10] arr;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64[10] arr;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .var_decl);
    try testing.expect(stmt.var_decl.type == .array);
    try testing.expectEqual(Type.i64, stmt.var_decl.type.array.element_type.*);
    try testing.expectEqual(@as(u64, 10), stmt.var_decl.type.array.size.?);
    try testing.expectEqualStrings("arr", stmt.var_decl.name);
}

test "Parse expression statement: x = 42;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "x = 42;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .expr);
    try testing.expect(stmt.expr.expr == .binary);
    try testing.expectEqual(BinaryOp.assign, stmt.expr.expr.binary.op);
}

test "Parse expression statement: func(a, b);" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "func(a, b);";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .expr);
    try testing.expect(stmt.expr.expr == .call);
    try testing.expectEqualStrings("func", stmt.expr.expr.call.callee.identifier.name);
    try testing.expectEqual(@as(usize, 2), stmt.expr.expr.call.args.len);
}

test "Parse expression statement: x++;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "x++;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .expr);
    try testing.expect(stmt.expr.expr == .unary);
    try testing.expectEqual(UnaryOp.post_increment, stmt.expr.expr.unary.op);
}

// ============================================================================
// Control Flow Statement Tests
// ============================================================================

test "Parse block statement: { x = 1; y = 2; }" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "{ x = 1; y = 2; }";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .block);
    try testing.expectEqual(@as(usize, 2), stmt.block.stmts.len);
}

test "Parse empty block: {}" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "{}";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .block);
    try testing.expectEqual(@as(usize, 0), stmt.block.stmts.len);
}

test "Parse if statement: if (x) y = 1;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "if (x) y = 1;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .if_stmt);
    try testing.expectEqualStrings("x", stmt.if_stmt.condition.identifier.name);
    try testing.expect(stmt.if_stmt.then_stmt.* == .expr);
    try testing.expect(stmt.if_stmt.else_stmt == null);
}

test "Parse if-else statement: if (x) y = 1; else y = 2;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "if (x) y = 1; else y = 2;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .if_stmt);
    try testing.expect(stmt.if_stmt.else_stmt != null);
    try testing.expect(stmt.if_stmt.else_stmt.?.* == .expr);
}

test "Parse while statement: while (x) y++;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "while (x) y++;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .while_stmt);
    try testing.expectEqualStrings("x", stmt.while_stmt.condition.identifier.name);
    try testing.expect(stmt.while_stmt.body.* == .expr);
}

test "Parse do-while statement: do x++; while (x < 10);" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "do x++; while (x < 10);";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .do_while);
    try testing.expect(stmt.do_while.body.* == .expr);
    try testing.expect(stmt.do_while.condition == .binary);
}

test "Parse for statement: for (i = 0; i < 10; i++) sum += i;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "for (i = 0; i < 10; i++) sum += i;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .for_stmt);
    try testing.expect(stmt.for_stmt.init != null);
    try testing.expect(stmt.for_stmt.condition != null);
    try testing.expect(stmt.for_stmt.increment != null);
}

test "Parse for statement with declaration: for (I64 i = 0; i < 10; i++) x++;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "for (I64 i = 0; i < 10; i++) x++;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .for_stmt);
    try testing.expect(stmt.for_stmt.init != null);
    try testing.expect(stmt.for_stmt.init.?.* == .var_decl);
}

test "Parse return statement: return 42;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "return 42;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .return_stmt);
    try testing.expect(stmt.return_stmt.expr != null);
    try testing.expectEqual(@as(i64, 42), stmt.return_stmt.expr.?.integer.value);
}

test "Parse return statement with no value: return;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "return;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .return_stmt);
    try testing.expect(stmt.return_stmt.expr == null);
}

test "Parse break statement: break;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "break;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .break_stmt);
}

test "Parse nested blocks" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "{ { x = 1; } }";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .block);
    try testing.expectEqual(@as(usize, 1), stmt.block.stmts.len);
    try testing.expect(stmt.block.stmts[0] == .block);
}

// ============================================================================
// Declaration Tests
// ============================================================================

test "Parse simple function: U0 Main() { }" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "U0 Main() { }";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const program = try parser.parse();
    try testing.expectEqual(@as(usize, 1), program.decls.len);
    try testing.expect(program.decls[0] == .function);
    try testing.expectEqualStrings("Main", program.decls[0].function.name);
    try testing.expect(program.decls[0].function.body != null);
}

test "Parse function with parameters: I64 Add(I64 a, I64 b) { }" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64 Add(I64 a, I64 b) { }";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const program = try parser.parse();
    try testing.expectEqual(@as(usize, 1), program.decls.len);
    try testing.expect(program.decls[0] == .function);
    try testing.expectEqualStrings("Add", program.decls[0].function.name);
    try testing.expectEqual(@as(usize, 2), program.decls[0].function.params.len);
    try testing.expectEqualStrings("a", program.decls[0].function.params[0].name);
    try testing.expectEqualStrings("b", program.decls[0].function.params[1].name);
}

test "Parse global variable: I64 x = 42;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64 x = 42;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const program = try parser.parse();
    try testing.expectEqual(@as(usize, 1), program.decls.len);
    try testing.expect(program.decls[0] == .global_var);
    try testing.expectEqualStrings("x", program.decls[0].global_var.name);
    try testing.expect(program.decls[0].global_var.init != null);
}

test "Parse simple class: class MyClass { I64 x; };" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "class MyClass { I64 x; };";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const program = try parser.parse();
    try testing.expectEqual(@as(usize, 1), program.decls.len);
    try testing.expect(program.decls[0] == .class);
    try testing.expectEqualStrings("MyClass", program.decls[0].class.name);
    try testing.expectEqual(@as(usize, 1), program.decls[0].class.members.len);
}

test "Parse class with repr type: I64 class CDate { U32 time; };" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "I64 class CDate { U32 time; };";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const program = try parser.parse();
    try testing.expectEqual(@as(usize, 1), program.decls.len);
    try testing.expect(program.decls[0] == .class);
    try testing.expectEqualStrings("CDate", program.decls[0].class.name);
    try testing.expect(program.decls[0].class.repr_type != null);
}

test "Parse sizeof expression: sizeof(I64)" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "sizeof(I64)";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expect(expr == .sizeof_type);
}

test "Parse type cast: (I64*)ptr" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "(I64*)ptr";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const expr = try parser.parseExpression();
    try testing.expect(expr == .cast);
}

test "Parse switch statement: switch(x) { case 1: break; }" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "switch(x) { case 1: break; }";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .switch_stmt);
    try testing.expectEqual(@as(usize, 1), stmt.switch_stmt.cases.len);
}

test "Parse goto statement: goto finish;" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "goto finish;";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .goto_stmt);
    try testing.expectEqualStrings("finish", stmt.goto_stmt.label);
}

test "Parse try-catch: try { } catch { }" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = "try { x = 1; } catch { y = 2; }";
    var lex = Lexer.init(allocator, source);
    var parser = try Parser.init(allocator, &lex);

    const stmt = try parser.parseStatement();
    try testing.expect(stmt == .try_catch);
}
