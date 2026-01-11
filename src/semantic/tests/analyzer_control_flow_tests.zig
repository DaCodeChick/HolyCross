//! Control flow tests: loops, break, goto, labels, switch
const std = @import("std");
const testing = std.testing;
const analyzer_module = @import("../analyzer.zig");
const ast = @import("../../parser/ast.zig");
const test_helpers = @import("test_helpers.zig");

const Analyzer = analyzer_module.Analyzer;

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.duplicate_label, analyzer.errors.items[0].kind);
}
