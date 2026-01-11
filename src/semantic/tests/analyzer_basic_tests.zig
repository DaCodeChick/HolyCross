//! Basic analyzer initialization and empty program tests
const std = @import("std");
const testing = std.testing;
const analyzer_module = @import("../analyzer.zig");
const ast = @import("../../parser/ast.zig");
const test_helpers = @import("test_helpers.zig");

const Analyzer = analyzer_module.Analyzer;

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

    const program = try test_helpers.createTestProgram(testing.allocator, &[_]ast.Decl{});

    try analyzer.analyze(program);
    try testing.expectEqual(@as(usize, 0), analyzer.errors.items.len);
}
