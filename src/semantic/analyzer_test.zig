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
