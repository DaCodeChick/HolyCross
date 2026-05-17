//! Declaration tests: functions, classes, unions, globals
const std = @import("std");
const testing = std.testing;
const analyzer_module = @import("../analyzer.zig");
const ast = @import("../../parser/ast.zig");
const test_helpers = @import("test_helpers.zig");

const Analyzer = analyzer_module.Analyzer;

test "Analyzer: simple function declaration" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const func_decl = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "TestFunc",
            .params = &[_]ast.Param{},
        .is_variadic = false,
            .body = null, // Forward declaration
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
    try testing.expect(analyzer.symbol_table.isFunctionDefined("TestFunc"));
}

test "Analyzer: duplicate function declaration" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const func1 = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "DuplicateFunc",
            .params = &[_]ast.Param{},
        .is_variadic = false,
            .body = null,
            .attributes = .{},
            .loc = loc,
        },
    };
    const func2 = ast.Decl{
        .function = .{
            .return_type = .f64,
            .name = "DuplicateFunc",
            .params = &[_]ast.Param{},
        .is_variadic = false,
            .body = null,
            .attributes = .{},
            .loc = .{ .line = 5, .column = 1 },
        },
    };

    var decls = [_]ast.Decl{ func1, func2 };
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}

// ============================================================================
// Class/Union Validation Tests
// ============================================================================

test "Analyzer: class declaration with members" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const member1 = ast.ClassMember{ .type = .i64, .name = "x", .loc = loc };
    const member2 = ast.ClassMember{ .type = .f64, .name = "y", .loc = loc };
    var members = [_]ast.ClassMember{ member1, member2 };

    const class_decl = ast.Decl{
        .class = .{
            .name = "Point",
            .alias = null,
            .repr_type = null,
            .base_class = null,
            .is_public = false,
            .is_static = false,
            .is_extern = false,
            .members = &members,
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{class_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);

    // Verify class is in symbol table
    const symbol = analyzer.symbol_table.lookupSymbol("Point");
    try testing.expect(symbol != null);
    try testing.expect(symbol.? == .type_def);
}

test "Analyzer: duplicate class member" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const member1 = ast.ClassMember{ .type = .i64, .name = "value", .loc = loc };
    const member2 = ast.ClassMember{ .type = .f64, .name = "value", .loc = .{ .line = 2, .column = 1 } };
    var members = [_]ast.ClassMember{ member1, member2 };

    const class_decl = ast.Decl{
        .class = .{
            .name = "TestClass",
            .alias = null,
            .repr_type = null,
            .base_class = null,
            .is_public = false,
            .is_static = false,
            .is_extern = false,
            .members = &members,
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{class_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}

test "Analyzer: union declaration with members" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const member1 = ast.ClassMember{ .type = .i64, .name = "as_int", .loc = loc };
    const member2 = ast.ClassMember{ .type = .f64, .name = "as_float", .loc = loc };
    var members = [_]ast.ClassMember{ member1, member2 };

    const union_decl = ast.Decl{
        .union_decl = .{
            .name = "Value",
            .alias = null,
            .repr_type = null,
            .is_public = false,
            .is_static = false,
            .is_extern = false,
            .members = &members,
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{union_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);

    // Verify union is in symbol table
    const symbol = analyzer.symbol_table.lookupSymbol("Value");
    try testing.expect(symbol != null);
    try testing.expect(symbol.? == .type_def);
}

test "Analyzer: duplicate union member" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const member1 = ast.ClassMember{ .type = .i32, .name = "data", .loc = loc };
    const member2 = ast.ClassMember{ .type = .u32, .name = "data", .loc = .{ .line = 2, .column = 1 } };
    var members = [_]ast.ClassMember{ member1, member2 };

    const union_decl = ast.Decl{
        .union_decl = .{
            .name = "TestUnion",
            .alias = null,
            .repr_type = null,
            .is_public = false,
            .is_static = false,
            .is_extern = false,
            .members = &members,
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{union_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}

test "Analyzer: global variable with valid initializer" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const init_expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const global_var = ast.Decl{
        .global_var = .{
            .type = .i64,
            .name = "GlobalCounter",
            .init = init_expr,
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{global_var};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);

    // Verify global variable is in symbol table
    const symbol = analyzer.symbol_table.lookupSymbol("GlobalCounter");
    try testing.expect(symbol != null);
}

test "Analyzer: duplicate global variable" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const init_expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const global_var1 = ast.Decl{
        .global_var = .{
            .type = .i64,
            .name = "GlobalVar",
            .init = init_expr,
            .loc = loc,
        },
    };
    const global_var2 = ast.Decl{
        .global_var = .{
            .type = .i64,
            .name = "GlobalVar",
            .init = init_expr,
            .loc = .{ .line = 5, .column = 1 },
        },
    };

    var decls = [_]ast.Decl{ global_var1, global_var2 };
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}
