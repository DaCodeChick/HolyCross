const std = @import("std");
const ast = @import("../../parser/ast.zig");

/// Helper to create a test Program - semantic tests don't heap-allocate AST nodes,
/// so we just create an empty arena to satisfy the struct definition
pub fn createTestProgram(allocator: std.mem.Allocator, decls: []const ast.Decl) !ast.Program {
    // Create an empty arena (won't be used for allocations in these tests)
    const arena = std.heap.ArenaAllocator.init(allocator);

    return ast.Program{
        .decls = @constCast(decls),
        .allocator = allocator,
        .arena = arena,
    };
}
