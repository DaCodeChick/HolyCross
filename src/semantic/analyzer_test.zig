const std = @import("std");
const testing = std.testing;
const analyzer_module = @import("analyzer.zig");
const ast = @import("../parser/ast.zig");

const Analyzer = analyzer_module.Analyzer;

// Helper to create a test Program - semantic tests don't heap-allocate AST nodes,
// so we just create an empty arena to satisfy the struct definition
fn createTestProgram(allocator: std.mem.Allocator, decls: []const ast.Decl) !ast.Program {
    // Create an empty arena (won't be used for allocations in these tests)
    const arena = std.heap.ArenaAllocator.init(allocator);

    return ast.Program{
        .decls = @constCast(decls),
        .allocator = allocator,
        .arena = arena,
    };
}

// ============================================================================
// Basic Analyzer Tests
// ============================================================================

test "Analyzer: init and deinit" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    try testing.expect(analyzer.errors.items.len == 0);
    try testing.expect(analyzer.loop_depth == 0);
}

test "Analyzer: empty program analysis" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const program = try createTestProgram(testing.allocator, &[_]ast.Decl{});

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

// ============================================================================
// Function Declaration Tests
// ============================================================================

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
            .body = null, // Forward declaration
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

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
            .body = null,
            .attributes = .{},
            .loc = .{ .line = 5, .column = 1 },
        },
    };

    var decls = [_]ast.Decl{ func1, func2 };
    const program = try createTestProgram(testing.allocator, &decls);

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
    const program = try createTestProgram(testing.allocator, &decls);

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
    const program = try createTestProgram(testing.allocator, &decls);

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
    const program = try createTestProgram(testing.allocator, &decls);

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
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}

test "Analyzer: break outside loop" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const break_stmt = ast.Stmt{ .break_stmt = .{ .loc = loc } };
    var stmts = [_]ast.Stmt{break_stmt};
    const block = ast.Stmt{
        .block = .{
            .stmts = &stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "BadBreak",
            .params = &[_]ast.Param{},
            .body = block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.invalid_break, analyzer.errors.items[0].kind);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

test "Analyzer: function with nested scopes and variable shadowing" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Outer scope variable
    const outer_var = ast.Stmt{
        .var_decl = .{
            .type = .i64,
            .name = "x",
            .init = ast.Expr{ .integer = .{ .value = 10, .loc = loc } },
            .loc = loc,
        },
    };

    // Inner block with shadowing variable
    const inner_var = ast.Stmt{
        .var_decl = .{
            .type = .f64,
            .name = "x", // Shadows outer x
            .init = ast.Expr{ .float = .{ .value = 3.14, .loc = loc } },
            .loc = .{ .line = 3, .column = 1 },
        },
    };
    var inner_stmts = [_]ast.Stmt{inner_var};
    const inner_block = ast.Stmt{
        .block = .{
            .stmts = &inner_stmts,
            .loc = .{ .line = 2, .column = 1 },
        },
    };

    var outer_stmts = [_]ast.Stmt{ outer_var, inner_block };
    const outer_block = ast.Stmt{
        .block = .{
            .stmts = &outer_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "TestShadowing",
            .params = &[_]ast.Param{},
            .body = outer_block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    // Shadowing should be allowed (no error)
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: function calling another function" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Define helper function
    const helper_ret_expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const helper_ret = ast.Stmt{ .return_stmt = .{ .expr = helper_ret_expr, .loc = loc } };
    var helper_stmts = [_]ast.Stmt{helper_ret};
    const helper_body = ast.Stmt{
        .block = .{
            .stmts = &helper_stmts,
            .loc = loc,
        },
    };
    const helper_func = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "Helper",
            .params = &[_]ast.Param{},
            .body = helper_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    // Define main function that calls helper
    var callee = ast.Expr{ .identifier = .{ .name = "Helper", .loc = loc } };
    var call_args = [_]ast.Expr{};
    const call_expr = ast.Expr{
        .call = .{
            .callee = &callee,
            .args = &call_args,
            .loc = loc,
        },
    };
    const call_stmt = ast.Stmt{ .expr = .{ .expr = call_expr, .loc = loc } };
    var main_stmts = [_]ast.Stmt{call_stmt};
    const main_body = ast.Stmt{
        .block = .{
            .stmts = &main_stmts,
            .loc = loc,
        },
    };
    const main_func = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Main",
            .params = &[_]ast.Param{},
            .body = main_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{ helper_func, main_func };
    const program = try createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: function with multiple return paths" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Create a condition
    const condition = ast.Expr{ .integer = .{ .value = 1, .loc = loc } };

    // Then branch with return
    const then_ret_expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const then_ret = ast.Stmt{ .return_stmt = .{ .expr = then_ret_expr, .loc = loc } };
    var then_stmts = [_]ast.Stmt{then_ret};
    var then_block = ast.Stmt{
        .block = .{
            .stmts = &then_stmts,
            .loc = loc,
        },
    };

    // Else branch with return
    const else_ret_expr = ast.Expr{ .integer = .{ .value = 0, .loc = loc } };
    const else_ret = ast.Stmt{ .return_stmt = .{ .expr = else_ret_expr, .loc = loc } };
    var else_stmts = [_]ast.Stmt{else_ret};
    var else_block = ast.Stmt{
        .block = .{
            .stmts = &else_stmts,
            .loc = loc,
        },
    };

    // If statement
    const if_stmt = ast.Stmt{
        .if_stmt = .{
            .condition = condition,
            .then_stmt = &then_block,
            .else_stmt = &else_block,
            .loc = loc,
        },
    };

    var func_stmts = [_]ast.Stmt{if_stmt};
    const func_body = ast.Stmt{
        .block = .{
            .stmts = &func_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "GetValue",
            .params = &[_]ast.Param{},
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    // This should pass - we have return in both branches
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: while loop with break" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    const condition = ast.Expr{ .integer = .{ .value = 1, .loc = loc } };
    const break_stmt = ast.Stmt{ .break_stmt = .{ .loc = loc } };
    var body_stmts = [_]ast.Stmt{break_stmt};
    var loop_body = ast.Stmt{
        .block = .{
            .stmts = &body_stmts,
            .loc = loc,
        },
    };

    const while_stmt = ast.Stmt{
        .while_stmt = .{
            .condition = condition,
            .body = &loop_body,
            .loc = loc,
        },
    };

    var func_stmts = [_]ast.Stmt{while_stmt};
    const func_body = ast.Stmt{
        .block = .{
            .stmts = &func_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Loop",
            .params = &[_]ast.Param{},
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: empty switch statement" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    const condition = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    var empty_cases = [_]ast.SwitchCase{};

    const switch_stmt = ast.Stmt{
        .switch_stmt = .{
            .expr = condition,
            .cases = &empty_cases,
            .loc = loc,
        },
    };

    var func_stmts = [_]ast.Stmt{switch_stmt};
    const func_body = ast.Stmt{
        .block = .{
            .stmts = &func_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "TestSwitch",
            .params = &[_]ast.Param{},
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: duplicate label" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const label1 = ast.Stmt{ .label = .{ .name = "MyLabel", .loc = loc } };
    const label2 = ast.Stmt{ .label = .{ .name = "MyLabel", .loc = .{ .line = 5, .column = 1 } } };
    var stmts = [_]ast.Stmt{ label1, label2 };
    const block = ast.Stmt{
        .block = .{
            .stmts = &stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "DuplicateLabel",
            .params = &[_]ast.Param{},
            .body = block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}

// ============================================================================
// Control Flow Analysis Tests
// ============================================================================

test "Analyzer: unreachable code after return" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Return statement
    const ret_expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const ret_stmt = ast.Stmt{ .return_stmt = .{ .expr = ret_expr, .loc = loc } };

    // Unreachable variable declaration after return
    const unreachable_var = ast.Stmt{
        .var_decl = .{
            .type = .i64,
            .name = "x",
            .init = ast.Expr{ .integer = .{ .value = 10, .loc = .{ .line = 3, .column = 1 } } },
            .loc = .{ .line = 3, .column = 1 },
        },
    };

    var func_stmts = [_]ast.Stmt{ ret_stmt, unreachable_var };
    const func_body = ast.Stmt{
        .block = .{
            .stmts = &func_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "Test",
            .params = &[_]ast.Param{},
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.unreachable_code, analyzer.errors.items[0].kind);
}

test "Analyzer: unreachable code after break" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Break statement
    const break_stmt = ast.Stmt{ .break_stmt = .{ .loc = loc } };

    // Unreachable statement after break
    const unreachable_expr = ast.Stmt{
        .expr = .{
            .expr = ast.Expr{ .integer = .{ .value = 10, .loc = .{ .line = 3, .column = 1 } } },
            .loc = .{ .line = 3, .column = 1 },
        },
    };

    var loop_stmts = [_]ast.Stmt{ break_stmt, unreachable_expr };
    var loop_body = ast.Stmt{
        .block = .{
            .stmts = &loop_stmts,
            .loc = loc,
        },
    };

    const condition = ast.Expr{ .integer = .{ .value = 1, .loc = loc } };
    const while_stmt = ast.Stmt{
        .while_stmt = .{
            .condition = condition,
            .body = &loop_body,
            .loc = loc,
        },
    };

    var func_stmts = [_]ast.Stmt{while_stmt};
    const func_body = ast.Stmt{
        .block = .{
            .stmts = &func_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Test",
            .params = &[_]ast.Param{},
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.unreachable_code, analyzer.errors.items[0].kind);
}

test "Analyzer: reachable code (no false positives)" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Variable declaration
    const var_decl = ast.Stmt{
        .var_decl = .{
            .type = .i64,
            .name = "x",
            .init = ast.Expr{ .integer = .{ .value = 10, .loc = loc } },
            .loc = loc,
        },
    };

    // Return statement after variable (reachable)
    const ret_expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const ret_stmt = ast.Stmt{ .return_stmt = .{ .expr = ret_expr, .loc = loc } };

    var func_stmts = [_]ast.Stmt{ var_decl, ret_stmt };
    const func_body = ast.Stmt{
        .block = .{
            .stmts = &func_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "Test",
            .params = &[_]ast.Param{},
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    // Should pass - all code is reachable
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: context tracking reset per function" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // First function with a label
    const label1 = ast.Stmt{ .label = .{ .name = "Label1", .loc = loc } };
    var stmts1 = [_]ast.Stmt{label1};
    const block1 = ast.Stmt{
        .block = .{
            .stmts = &stmts1,
            .loc = loc,
        },
    };
    const func1 = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Func1",
            .params = &[_]ast.Param{},
            .body = block1,
            .attributes = .{},
            .loc = loc,
        },
    };

    // Second function with same label name (should be OK in different function)
    const label2 = ast.Stmt{ .label = .{ .name = "Label1", .loc = loc } };
    var stmts2 = [_]ast.Stmt{label2};
    const block2 = ast.Stmt{
        .block = .{
            .stmts = &stmts2,
            .loc = loc,
        },
    };
    const func2 = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Func2",
            .params = &[_]ast.Param{},
            .body = block2,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{ func1, func2 };
    const program = try createTestProgram(testing.allocator, &decls);

    // Both functions should analyze successfully - labels are scoped to functions
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

// ============================================================================
// Advanced Validation Tests
// ============================================================================

test "Analyzer: goto with undefined label" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const goto_stmt = ast.Stmt{ .goto_stmt = .{ .label = "NonExistentLabel", .loc = loc } };
    var stmts = [_]ast.Stmt{goto_stmt};
    const block = ast.Stmt{
        .block = .{
            .stmts = &stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "TestGoto",
            .params = &[_]ast.Param{},
            .body = block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.invalid_break, analyzer.errors.items[0].kind);
}

test "Analyzer: goto with valid label" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const label = ast.Stmt{ .label = .{ .name = "MyLabel", .loc = loc } };
    const goto_stmt = ast.Stmt{ .goto_stmt = .{ .label = "MyLabel", .loc = loc } };
    var stmts = [_]ast.Stmt{ label, goto_stmt };
    const block = ast.Stmt{
        .block = .{
            .stmts = &stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "TestGoto",
            .params = &[_]ast.Param{},
            .body = block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: missing return statement in non-void function" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    var empty_stmts = [_]ast.Stmt{};
    const block = ast.Stmt{
        .block = .{
            .stmts = &empty_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .i64, // Non-void return type
            .name = "GetValue",
            .params = &[_]ast.Param{},
            .body = block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.missing_return, analyzer.errors.items[0].kind);
}

test "Analyzer: non-void function with return statement" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const int_expr = ast.Expr{ .integer = .{ .value = 42, .loc = loc } };
    const return_stmt = ast.Stmt{ .return_stmt = .{ .expr = int_expr, .loc = loc } };
    var stmts = [_]ast.Stmt{return_stmt};
    const block = ast.Stmt{
        .block = .{
            .stmts = &stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "GetValue",
            .params = &[_]ast.Param{},
            .body = block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try createTestProgram(testing.allocator, &decls);

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: function call with wrong argument count" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Declare a function that takes 2 parameters
    const param1 = ast.Param{ .type = .i64, .name = "a", .loc = loc };
    const param2 = ast.Param{ .type = .i64, .name = "b", .loc = loc };
    var params = [_]ast.Param{ param1, param2 };
    var empty_stmts = [_]ast.Stmt{};
    const func1_body = ast.Stmt{
        .block = .{
            .stmts = &empty_stmts,
            .loc = loc,
        },
    };
    const func1 = ast.Decl{
        .function = .{
            .return_type = .i64,
            .name = "Add",
            .params = &params,
            .body = func1_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    // Call the function with only 1 argument
    var func_id = ast.Expr{ .identifier = .{ .name = "Add", .loc = loc } };
    const arg1 = ast.Expr{ .integer = .{ .value = 10, .loc = loc } };
    var call_args = [_]ast.Expr{arg1};
    const call_expr = ast.Expr{
        .call = .{
            .callee = &func_id,
            .args = &call_args,
            .loc = loc,
        },
    };
    const expr_stmt = ast.Stmt{ .expr = .{ .expr = call_expr, .loc = loc } };
    var caller_stmts = [_]ast.Stmt{expr_stmt};
    const caller_body = ast.Stmt{
        .block = .{
            .stmts = &caller_stmts,
            .loc = loc,
        },
    };
    const caller = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Main",
            .params = &[_]ast.Param{},
            .body = caller_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{ func1, caller };
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.argument_count_mismatch, analyzer.errors.items[0].kind);
}

test "Analyzer: function call with wrong argument type" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Declare a function that takes an i64 parameter
    const param = ast.Param{ .type = .i64, .name = "x", .loc = loc };
    var params = [_]ast.Param{param};
    var empty_stmts = [_]ast.Stmt{};
    const func1_body = ast.Stmt{
        .block = .{
            .stmts = &empty_stmts,
            .loc = loc,
        },
    };
    const func1 = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "ProcessInt",
            .params = &params,
            .body = func1_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    // Call the function with a string argument
    var func_id = ast.Expr{ .identifier = .{ .name = "ProcessInt", .loc = loc } };
    const str_arg = ast.Expr{ .string = .{ .value = "hello", .loc = loc } };
    var call_args = [_]ast.Expr{str_arg};
    const call_expr = ast.Expr{
        .call = .{
            .callee = &func_id,
            .args = &call_args,
            .loc = loc,
        },
    };
    const expr_stmt = ast.Stmt{ .expr = .{ .expr = call_expr, .loc = loc } };
    var caller_stmts = [_]ast.Stmt{expr_stmt};
    const caller_body = ast.Stmt{
        .block = .{
            .stmts = &caller_stmts,
            .loc = loc,
        },
    };
    const caller = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Main",
            .params = &[_]ast.Param{},
            .body = caller_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{ func1, caller };
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.argument_type_mismatch, analyzer.errors.items[0].kind);
}

test "Analyzer: call to undeclared function" {
    var analyzer = Analyzer.init(testing.allocator);
    analyzer.initTypeChecker();
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Call an undeclared function
    var func_id = ast.Expr{ .identifier = .{ .name = "UndeclaredFunc", .loc = loc } };
    var call_args = [_]ast.Expr{};
    const call_expr = ast.Expr{
        .call = .{
            .callee = &func_id,
            .args = &call_args,
            .loc = loc,
        },
    };
    const expr_stmt = ast.Stmt{ .expr = .{ .expr = call_expr, .loc = loc } };
    var caller_stmts = [_]ast.Stmt{expr_stmt};
    const caller_body = ast.Stmt{
        .block = .{
            .stmts = &caller_stmts,
            .loc = loc,
        },
    };
    const caller = ast.Decl{
        .function = .{
            .return_type = .u0,
            .name = "Main",
            .params = &[_]ast.Param{},
            .body = caller_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{caller};
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.undeclared_identifier, analyzer.errors.items[0].kind);
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
    const program = try createTestProgram(testing.allocator, &decls);

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
    const program = try createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}
