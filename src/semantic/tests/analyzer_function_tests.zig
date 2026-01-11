//! Function-related tests: calls, returns, scoping, parameters
const std = @import("std");
const testing = std.testing;
const analyzer_module = @import("../analyzer.zig");
const ast = @import("../../parser/ast.zig");
const test_helpers = @import("test_helpers.zig");

const Analyzer = analyzer_module.Analyzer;

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    // This should pass - we have return in both branches
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.undefined_label, analyzer.errors.items[0].kind);
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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    // Add a return statement so we don't get missing_return error
    const return_expr = ast.Expr{ .integer = .{ .value = 0, .loc = loc } };
    const return_stmt = ast.Stmt{ .return_stmt = .{ .expr = return_expr, .loc = loc } };
    var func1_stmts = [_]ast.Stmt{return_stmt};
    const func1_body = ast.Stmt{
        .block = .{
            .stmts = &func1_stmts,
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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.argument_count_mismatch, analyzer.errors.items[0].kind);
}

test "Analyzer: function call with implicit type conversion" {
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

    // Call the function with a string argument (U8*)
    // HolyC allows pointer-to-integer conversion, so this should succeed
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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    // This should succeed because HolyC allows pointer-to-integer conversion
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.undeclared_identifier, analyzer.errors.items[0].kind);
}

