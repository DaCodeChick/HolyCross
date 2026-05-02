const std = @import("std");
const testing = std.testing;
const type_checker = @import("../type_checker.zig");
const symbol_table = @import("../symbol_table.zig");
const ast = @import("../../parser/ast.zig");

const TypeChecker = type_checker.TypeChecker;
const SymbolTable = symbol_table.SymbolTable;

// ============================================================================
// Type Classification Tests
// ============================================================================

test "TypeChecker: isIntegerType" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    try testing.expect(checker.isIntegerType(.i8));
    try testing.expect(checker.isIntegerType(.i16));
    try testing.expect(checker.isIntegerType(.i32));
    try testing.expect(checker.isIntegerType(.i64));
    try testing.expect(checker.isIntegerType(.u8));
    try testing.expect(checker.isIntegerType(.u16));
    try testing.expect(checker.isIntegerType(.u32));
    try testing.expect(checker.isIntegerType(.u64));

    try testing.expect(!checker.isIntegerType(.f64));
}

test "TypeChecker: isFloatType" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    try testing.expect(checker.isFloatType(.f64));
    try testing.expect(!checker.isFloatType(.i64));
    try testing.expect(!checker.isFloatType(.u32));
}

test "TypeChecker: isNumericType" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    try testing.expect(checker.isNumericType(.i32));
    try testing.expect(checker.isNumericType(.u64));
    try testing.expect(checker.isNumericType(.f64));
}

test "TypeChecker: getIntegerSize" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    try testing.expectEqual(@as(u32, 8), checker.getIntegerSize(.i8));
    try testing.expectEqual(@as(u32, 16), checker.getIntegerSize(.i16));
    try testing.expectEqual(@as(u32, 32), checker.getIntegerSize(.i32));
    try testing.expectEqual(@as(u32, 64), checker.getIntegerSize(.i64));
}

// ============================================================================
// Type Compatibility Tests
// ============================================================================

test "TypeChecker: areTypesCompatible - exact match" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    try testing.expect(try checker.areTypesCompatible(.i64, .i64));
    try testing.expect(try checker.areTypesCompatible(.f64, .f64));
}

test "TypeChecker: areTypesCompatible - integer to integer" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    // HolyC allows all integer conversions
    try testing.expect(try checker.areTypesCompatible(.i32, .i64));
    try testing.expect(try checker.areTypesCompatible(.i64, .i32));
    try testing.expect(try checker.areTypesCompatible(.u32, .i64));
}

test "TypeChecker: areTypesCompatible - integer to float" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    try testing.expect(try checker.areTypesCompatible(.i32, .f64));
    try testing.expect(try checker.areTypesCompatible(.u64, .f64));
}

// ============================================================================
// Expression Type Inference Tests
// ============================================================================

test "TypeChecker: inferExprType - integer literal" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const typ = try checker.inferExprType(expr);

    try testing.expectEqual(ast.Type.i64, typ);
}

test "TypeChecker: inferExprType - float literal" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const expr = ast.Expr{ .float = .{ .value = 3.14, .loc = loc } };
    const typ = try checker.inferExprType(expr);

    try testing.expectEqual(ast.Type.f64, typ);
}

test "TypeChecker: inferExprType - char literal" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const expr = ast.Expr{ .char = .{ .value = 'A', .loc = loc } };
    const typ = try checker.inferExprType(expr);

    try testing.expectEqual(ast.Type.i32, typ);
}

test "TypeChecker: inferExprType - identifier variable" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    try sym_table.enterGlobalScope();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    try sym_table.defineVariable("x", .i64, true, true, loc);

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    const expr = ast.Expr{ .identifier = .{ .name = "x", .loc = loc } };
    const typ = try checker.inferExprType(expr);

    try testing.expectEqual(ast.Type.i64, typ);
}

test "TypeChecker: inferExprType - undeclared identifier" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    try sym_table.enterGlobalScope();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const expr = ast.Expr{ .identifier = .{ .name = "undefined_var", .loc = loc } };
    const result = checker.inferExprType(expr);

    try testing.expectError(error.TypeError, result);
    try testing.expectEqual(@as(usize, 1), checker.errors.items.len);
}

// ============================================================================
// Binary Operation Type Tests
// ============================================================================

test "TypeChecker: arithmetic operation promotes to larger type" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    const promoted = checker.promoteIntegerTypes(.i32, .i64);
    try testing.expectEqual(ast.Type.i64, promoted);

    const promoted2 = checker.promoteIntegerTypes(.u16, .u32);
    try testing.expectEqual(ast.Type.u32, promoted2);
}

test "TypeChecker: arithmetic with float returns float" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    var class_members = std.StringHashMap([]ast.ClassMember).init(testing.allocator);
    defer class_members.deinit();
    var class_bases = std.StringHashMap([]const u8).init(testing.allocator);
    defer class_bases.deinit();

    var checker = TypeChecker.init(testing.allocator, &sym_table, &class_members, &class_bases);
    defer checker.deinit();

    const result = try checker.arithmeticResultType(.i64, .f64);
    try testing.expectEqual(ast.Type.f64, result);

    const result2 = try checker.arithmeticResultType(.f64, .i32);
    try testing.expectEqual(ast.Type.f64, result2);
}
