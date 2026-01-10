const std = @import("std");
const testing = std.testing;
const symbol_table = @import("symbol_table.zig");
const symbol_module = @import("symbol.zig");
const ast = @import("../parser/ast.zig");

const SymbolTable = symbol_table.SymbolTable;
const VariableSymbol = symbol_module.VariableSymbol;

// ============================================================================
// SymbolTable Tests
// ============================================================================

test "SymbolTable: Basic initialization and cleanup" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    try testing.expectEqual(@as(usize, 0), sym_table.currentDepth());
}

test "SymbolTable: Define and lookup variables" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    try sym_table.enterGlobalScope();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    try sym_table.defineVariable("x", .i64, true, true, loc);

    // Lookup should find the variable
    const symbol = sym_table.lookupSymbol("x");
    try testing.expect(symbol != null);
    try testing.expect(symbol.?.variable.is_global);
    try testing.expect(symbol.?.variable.is_mutable);
    try testing.expectEqualStrings("x", symbol.?.variable.name);

    // Validation helpers should work
    try testing.expect(sym_table.isVariableDefined("x"));
    try testing.expect(!sym_table.isFunctionDefined("x"));
    try testing.expect(!sym_table.isTypeDefined("x"));

    // Get variable info
    const var_info = sym_table.getVariable("x");
    try testing.expect(var_info != null);
    try testing.expectEqual(ast.Type.i64, var_info.?.type);
}

test "SymbolTable: Define and lookup functions" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    try sym_table.enterGlobalScope();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const params = [_]ast.Param{
        .{ .name = "a", .type = .i64, .loc = loc },
        .{ .name = "b", .type = .i64, .loc = loc },
    };

    try sym_table.defineFunction("Add", .i64, &params, loc);

    // Lookup should find the function
    const symbol = sym_table.lookupSymbol("Add");
    try testing.expect(symbol != null);
    try testing.expectEqualStrings("Add", symbol.?.function.name);
    try testing.expectEqual(ast.Type.i64, symbol.?.function.return_type);
    try testing.expectEqual(@as(usize, 2), symbol.?.function.params.len);

    // Validation helpers
    try testing.expect(sym_table.isFunctionDefined("Add"));
    try testing.expect(!sym_table.isVariableDefined("Add"));

    // Get function info
    const func_info = sym_table.getFunction("Add");
    try testing.expect(func_info != null);
    try testing.expectEqual(@as(usize, 2), func_info.?.params.len);
}

test "SymbolTable: Define and lookup types" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    try sym_table.enterGlobalScope();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    try sym_table.defineType("MyInt", .i64, loc);

    // Lookup should find the type
    const symbol = sym_table.lookupSymbol("MyInt");
    try testing.expect(symbol != null);
    try testing.expectEqualStrings("MyInt", symbol.?.type_def.name);

    // Validation helpers
    try testing.expect(sym_table.isTypeDefined("MyInt"));
    try testing.expect(!sym_table.isVariableDefined("MyInt"));

    // Get type info
    const type_info = sym_table.getType("MyInt");
    try testing.expect(type_info != null);
    try testing.expectEqual(ast.Type.i64, type_info.?.underlying_type);
}

test "SymbolTable: Duplicate definition error" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    try sym_table.enterGlobalScope();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    try sym_table.defineVariable("x", .i64, true, true, loc);

    // Trying to define again in same scope should error
    const result = sym_table.defineVariable("x", .i32, true, true, loc);
    try testing.expectError(error.SymbolAlreadyDefined, result);
}

test "SymbolTable: Nested scopes and shadowing" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Global scope
    try sym_table.enterGlobalScope();
    try sym_table.defineVariable("x", .i64, true, true, loc);

    // Function scope (shadows x)
    try sym_table.enterFunctionScope();
    try sym_table.defineVariable("x", .i32, false, true, loc);
    try sym_table.defineVariable("y", .f64, false, true, loc);

    // In function scope, x should be i32 (shadowed)
    const x_symbol = sym_table.lookupSymbol("x");
    try testing.expect(x_symbol != null);
    try testing.expectEqual(ast.Type.i32, x_symbol.?.variable.type);

    // y should be visible
    try testing.expect(sym_table.isVariableDefined("y"));

    // Exit function scope
    sym_table.exitScope();

    // Now x should be i64 (global) again
    const x_global = sym_table.lookupSymbol("x");
    try testing.expect(x_global != null);
    try testing.expectEqual(ast.Type.i64, x_global.?.variable.type);

    // y should not be visible
    try testing.expect(!sym_table.isVariableDefined("y"));
}

test "SymbolTable: Multiple scope levels" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    // Global scope (depth 0)
    try sym_table.enterGlobalScope();
    try testing.expectEqual(@as(usize, 1), sym_table.currentDepth());
    try sym_table.defineVariable("global", .i64, true, true, loc);

    // Function scope (depth 1)
    try sym_table.enterFunctionScope();
    try testing.expectEqual(@as(usize, 2), sym_table.currentDepth());
    try sym_table.defineVariable("func_var", .i32, false, true, loc);

    // Block scope (depth 2)
    try sym_table.enterBlockScope();
    try testing.expectEqual(@as(usize, 3), sym_table.currentDepth());
    try sym_table.defineVariable("block_var", .f64, false, true, loc);

    // All variables should be visible
    try testing.expect(sym_table.isVariableDefined("global"));
    try testing.expect(sym_table.isVariableDefined("func_var"));
    try testing.expect(sym_table.isVariableDefined("block_var"));

    // Exit block scope
    sym_table.exitScope();
    try testing.expectEqual(@as(usize, 2), sym_table.currentDepth());
    try testing.expect(!sym_table.isVariableDefined("block_var"));

    // Exit function scope
    sym_table.exitScope();
    try testing.expectEqual(@as(usize, 1), sym_table.currentDepth());
    try testing.expect(!sym_table.isVariableDefined("func_var"));

    // Global should still be visible
    try testing.expect(sym_table.isVariableDefined("global"));
}

test "SymbolTable: lookupLocal vs lookup" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    try sym_table.enterGlobalScope();
    try sym_table.defineVariable("x", .i64, true, true, loc);

    try sym_table.enterFunctionScope();

    // lookup should find global x
    try testing.expect(sym_table.lookupSymbol("x") != null);

    // lookupLocal should NOT find global x
    try testing.expect(sym_table.lookupLocal("x") == null);

    // Define local y
    try sym_table.defineVariable("y", .i32, false, true, loc);

    // Both should find local y
    try testing.expect(sym_table.lookupSymbol("y") != null);
    try testing.expect(sym_table.lookupLocal("y") != null);
}

test "SymbolTable: Mutability and global checks" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };

    try sym_table.enterGlobalScope();
    try sym_table.defineVariable("mutable_global", .i64, true, true, loc);
    try sym_table.defineVariable("const_local", .i32, false, false, loc);

    try testing.expect(sym_table.isMutable("mutable_global"));
    try testing.expect(!sym_table.isMutable("const_local"));

    try testing.expect(sym_table.isGlobal("mutable_global"));
    try testing.expect(!sym_table.isGlobal("const_local"));

    // Non-existent variable
    try testing.expect(!sym_table.isMutable("nonexistent"));
    try testing.expect(!sym_table.isGlobal("nonexistent"));
}

test "SymbolTable: Mixed symbol types in same scope" {
    var sym_table = SymbolTable.init(testing.allocator);
    defer sym_table.deinit();

    const loc = ast.SourceLocation{ .line = 1, .column = 1 };
    const params = [_]ast.Param{};

    try sym_table.enterGlobalScope();

    // Define different symbol types with different names
    try sym_table.defineVariable("x", .i64, true, true, loc);
    try sym_table.defineFunction("Add", .i64, &params, loc);
    try sym_table.defineType("MyType", .i32, loc);

    // Each should be found with correct type
    try testing.expect(sym_table.isVariableDefined("x"));
    try testing.expect(sym_table.isFunctionDefined("Add"));
    try testing.expect(sym_table.isTypeDefined("MyType"));

    // Wrong type checks should fail
    try testing.expect(!sym_table.isFunctionDefined("x"));
    try testing.expect(!sym_table.isTypeDefined("Add"));
    try testing.expect(!sym_table.isVariableDefined("MyType"));
}
