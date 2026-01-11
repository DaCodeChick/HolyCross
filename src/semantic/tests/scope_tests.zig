const std = @import("std");
const testing = std.testing;
const scope = @import("../scope.zig");
const symbol_module = @import("../symbol.zig");
const ast = @import("../../parser/ast.zig");

const Scope = scope.Scope;
const ScopeStack = scope.ScopeStack;
const Symbol = symbol_module.Symbol;
const VariableSymbol = symbol_module.VariableSymbol;

// ============================================================================
// Scope Tests
// ============================================================================

test "Scope: define and lookup local" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var test_scope = Scope.init(allocator, .global, null);
    defer test_scope.deinit();

    // Define a variable
    const var_symbol = Symbol{
        .variable = VariableSymbol{
            .name = "x",
            .type = .i64,
            .is_global = true,
            .is_mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    try test_scope.define(var_symbol);

    // Lookup the variable
    const found = test_scope.lookupLocal("x");
    try testing.expect(found != null);
    try testing.expectEqualStrings("x", found.?.getName());
}

test "Scope: duplicate definition error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var test_scope = Scope.init(allocator, .global, null);
    defer test_scope.deinit();

    const var_symbol = Symbol{
        .variable = VariableSymbol{
            .name = "x",
            .type = .i64,
            .is_global = true,
            .is_mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    try test_scope.define(var_symbol);

    // Try to define again - should error
    const result = test_scope.define(var_symbol);
    try testing.expectError(error.SymbolAlreadyDefined, result);
}

test "Scope: parent scope lookup" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parent scope
    var parent_scope = Scope.init(allocator, .global, null);
    defer parent_scope.deinit();

    const parent_var = Symbol{
        .variable = VariableSymbol{
            .name = "x",
            .type = .i64,
            .is_global = true,
            .is_mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    };
    try parent_scope.define(parent_var);

    // Child scope
    var child_scope = Scope.init(allocator, .block, &parent_scope);
    defer child_scope.deinit();

    const child_var = Symbol{
        .variable = VariableSymbol{
            .name = "y",
            .type = .i32,
            .is_global = false,
            .is_mutable = true,
            .loc = .{ .line = 2, .column = 1 },
        },
    };
    try child_scope.define(child_var);

    // Child can see both x and y
    try testing.expect(child_scope.lookup("x") != null);
    try testing.expect(child_scope.lookup("y") != null);

    // Parent can only see x
    try testing.expect(parent_scope.lookup("x") != null);
    try testing.expect(parent_scope.lookup("y") == null);
}

// ============================================================================
// ScopeStack Tests
// ============================================================================

test "ScopeStack: enter and exit scopes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = ScopeStack.init(allocator);
    defer stack.deinit();

    try testing.expectEqual(@as(usize, 0), stack.depth());

    try stack.enterScope(.global);
    try testing.expectEqual(@as(usize, 1), stack.depth());

    try stack.enterScope(.function);
    try testing.expectEqual(@as(usize, 2), stack.depth());

    try stack.enterScope(.block);
    try testing.expectEqual(@as(usize, 3), stack.depth());

    stack.exitScope();
    try testing.expectEqual(@as(usize, 2), stack.depth());

    stack.exitScope();
    try testing.expectEqual(@as(usize, 1), stack.depth());

    stack.exitScope();
    try testing.expectEqual(@as(usize, 0), stack.depth());
}

test "ScopeStack: nested scope symbol lookup" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = ScopeStack.init(allocator);
    defer stack.deinit();

    // Global scope
    try stack.enterScope(.global);
    try stack.define(Symbol{
        .variable = VariableSymbol{
            .name = "global_var",
            .type = .i64,
            .is_global = true,
            .is_mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    });

    // Function scope
    try stack.enterScope(.function);
    try stack.define(Symbol{
        .variable = VariableSymbol{
            .name = "param",
            .type = .i32,
            .is_global = false,
            .is_mutable = true,
            .loc = .{ .line = 2, .column = 1 },
        },
    });

    // Block scope
    try stack.enterScope(.block);
    try stack.define(Symbol{
        .variable = VariableSymbol{
            .name = "local",
            .type = .u8,
            .is_global = false,
            .is_mutable = true,
            .loc = .{ .line = 3, .column = 1 },
        },
    });

    // Can see all three variables from innermost scope
    try testing.expect(stack.lookup("global_var") != null);
    try testing.expect(stack.lookup("param") != null);
    try testing.expect(stack.lookup("local") != null);

    // Exit block scope
    stack.exitScope();

    // Can still see global_var and param, but not local
    try testing.expect(stack.lookup("global_var") != null);
    try testing.expect(stack.lookup("param") != null);
    try testing.expect(stack.lookup("local") == null);
}

test "ScopeStack: shadowing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = ScopeStack.init(allocator);
    defer stack.deinit();

    // Global scope - define x as I64
    try stack.enterScope(.global);
    try stack.define(Symbol{
        .variable = VariableSymbol{
            .name = "x",
            .type = .i64,
            .is_global = true,
            .is_mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    });

    // Block scope - shadow x as U32
    try stack.enterScope(.block);
    try stack.define(Symbol{
        .variable = VariableSymbol{
            .name = "x",
            .type = .u32,
            .is_global = false,
            .is_mutable = true,
            .loc = .{ .line = 2, .column = 1 },
        },
    });

    // Lookup should find the inner (shadowing) x
    const found = stack.lookup("x").?;
    try testing.expect(found == .variable);
    try testing.expectEqual(ast.Type.u32, found.variable.type);

    // Exit inner scope
    stack.exitScope();

    // Now should find the outer x
    const found_outer = stack.lookup("x").?;
    try testing.expect(found_outer == .variable);
    try testing.expectEqual(ast.Type.i64, found_outer.variable.type);
}
