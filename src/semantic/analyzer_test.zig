const std = @import("std");
const testing = std.testing;
const analyzer_module = @import("analyzer.zig");
const ast = @import("../parser/ast.zig");

const Analyzer = analyzer_module.Analyzer;

// ============================================================================
// Basic Analyzer Tests
// ============================================================================

test "Analyzer: init and deinit" {
    var analyzer = Analyzer.init(testing.allocator);
    defer analyzer.deinit();

    try testing.expect(analyzer.errors.items.len == 0);
    try testing.expect(analyzer.loop_depth == 0);
}

test "Analyzer: empty program analysis" {
    var analyzer = Analyzer.init(testing.allocator);
    defer analyzer.deinit();

    const program = ast.Program{
        .decls = &[_]ast.Decl{},
        .allocator = testing.allocator,
    };

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

// ============================================================================
// Function Declaration Tests
// ============================================================================

test "Analyzer: simple function declaration" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
    try testing.expect(analyzer.symbol_table.isFunctionDefined("TestFunc"));
}

test "Analyzer: duplicate function declaration" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}

// ============================================================================
// Statement Analysis Tests
// ============================================================================

test "Analyzer: function with empty block" {
    var analyzer = Analyzer.init(testing.allocator);
    defer analyzer.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    var empty_stmts = [_]ast.Stmt{};
    const empty_block = ast.Stmt{
        .block = .{
            .stmts = &empty_stmts,
            .loc = loc,
        },
    };

    const func_decl = ast.Decl{
        .function = .{
            .return_type = .u0, // void
            .name = "EmptyFunc",
            .params = &[_]ast.Param{},
            .body = empty_block,
            .attributes = .{},
            .loc = loc,
        },
    };

    var decls = [_]ast.Decl{func_decl};
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: break outside loop" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.invalid_break, analyzer.errors.items[0].kind);
}

test "Analyzer: duplicate label" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.duplicate_label, analyzer.errors.items[0].kind);
}

test "Analyzer: context tracking reset per function" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    // Both functions should analyze successfully - labels are scoped to functions
    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

// ============================================================================
// Advanced Validation Tests
// ============================================================================

test "Analyzer: goto with undefined label" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.undefined_label, analyzer.errors.items[0].kind);
}

test "Analyzer: goto with valid label" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: missing return statement in non-void function" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.missing_return, analyzer.errors.items[0].kind);
}

test "Analyzer: non-void function with return statement" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}

test "Analyzer: function call with wrong argument count" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.argument_count_mismatch, analyzer.errors.items[0].kind);
}

test "Analyzer: function call with wrong argument type" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.argument_type_mismatch, analyzer.errors.items[0].kind);
}

test "Analyzer: call to undeclared function" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expect(analyzer.errors.items.len > 0);
    try testing.expectEqual(analyzer_module.ErrorKind.undeclared_identifier, analyzer.errors.items[0].kind);
}

test "Analyzer: global variable with valid initializer" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);

    // Verify global variable is in symbol table
    const symbol = analyzer.symbol_table.lookupSymbol("GlobalCounter");
    try testing.expect(symbol != null);
}

test "Analyzer: duplicate global variable" {
    var analyzer = Analyzer.init(testing.allocator);
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
    const program = ast.Program{
        .decls = &decls,
        .allocator = testing.allocator,
    };

    const result = analyzer.analyze(program);
    try testing.expectError(error.SemanticError, result);
    try testing.expectEqual(@as(usize, 1), analyzer.errors.items.len);
    try testing.expectEqual(analyzer_module.ErrorKind.redeclared_identifier, analyzer.errors.items[0].kind);
}
