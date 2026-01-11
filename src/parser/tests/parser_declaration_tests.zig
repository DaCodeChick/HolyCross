//! Declaration parsing tests: functions, classes, unions, globals
const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const lexer = @import("../../lexer/lexer.zig");
const Lexer = lexer.Lexer;
const ast = @import("../ast.zig");

const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Type = ast.Type;

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
