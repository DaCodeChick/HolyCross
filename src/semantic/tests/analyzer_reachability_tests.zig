//! Code reachability analysis tests
const std = @import("std");
const testing = std.testing;
const analyzer_module = @import("../analyzer.zig");
const ast = @import("../../parser/ast.zig");
const test_helpers = @import("test_helpers.zig");

const Analyzer = analyzer_module.Analyzer;

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
        .is_variadic = false,
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
        .is_variadic = false,
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
        .is_variadic = false,
            .body = func_body,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

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
        .is_variadic = false,
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
        .is_variadic = false,
            .body = block2,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{ func1, func2 };
    const program = try test_helpers.createTestProgram(testing.allocator, &decls);

    // Both functions should analyze successfully - labels are scoped to functions
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}
