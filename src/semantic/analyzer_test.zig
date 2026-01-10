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
