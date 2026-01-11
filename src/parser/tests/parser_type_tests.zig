//! Type parsing tests: primitives, pointers, arrays, named types
const std = @import("std");
const Parser = @import("../parser.zig").Parser;
const lexer = @import("../../lexer/lexer.zig");
const Lexer = lexer.Lexer;
const ast = @import("../ast.zig");

const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const Type = ast.Type;

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
