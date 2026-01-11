const std = @import("std");
const ast = @import("../../parser/ast.zig");

/// Helper to create a test Program - semantic tests don't heap-allocate AST nodes,
/// so we just create an empty arena to satisfy the struct definition
pub fn createTestProgram(allocator: std.mem.Allocator, decls: []const ast.Decl) !ast.Program {
    // Create an empty arena (won't be used for allocations in these tests)
    const arena = std.heap.ArenaAllocator.init(allocator);

    // Empty top-level statements slice
    const empty_stmts = &[_]ast.Stmt{};

    return ast.Program{
        .decls = @constCast(decls),
        .top_level_stmts = empty_stmts,
        .allocator = allocator,
        .arena = arena,
    };
}
