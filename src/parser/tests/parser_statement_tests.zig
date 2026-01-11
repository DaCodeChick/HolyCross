//! Statement parsing tests: variable declarations, assignments, blocks
const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const lexer = @import("../../lexer/lexer.zig");
const Lexer = lexer.Lexer;
const ast = @import("../ast.zig");

const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Type = ast.Type;

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
