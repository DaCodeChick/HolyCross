//! Control flow parsing tests: if, while, for, switch, goto, try-catch
const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const lexer = @import("../../lexer/lexer.zig");
const Lexer = lexer.Lexer;
const ast = @import("../ast.zig");

const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Type = ast.Type;

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
