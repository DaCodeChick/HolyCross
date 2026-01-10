const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../parser/ast.zig");
const scope = @import("scope.zig");

/// SymbolTable provides a high-level API for managing symbols across different scopes.
/// It wraps the ScopeStack and provides domain-specific methods for defining and
/// looking up variables, functions, and types.
///
/// Usage:
///   var sym_table = SymbolTable.init(allocator);
///   defer sym_table.deinit();
///
///   try sym_table.enterGlobalScope();
///   try sym_table.defineVariable("x", .i64_type, true, false, location);
///   const symbol = sym_table.lookupSymbol("x");
pub const SymbolTable = struct {
    scope_stack: scope.ScopeStack,
    allocator: Allocator,

    /// Initialize a new symbol table
    pub fn init(allocator: Allocator) SymbolTable {
        return .{
            .scope_stack = scope.ScopeStack.init(allocator),
            .allocator = allocator,
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *SymbolTable) void {
        self.scope_stack.deinit();
    }

    // ============================================================================
    // Scope Management
    // ============================================================================

    /// Enter a new global scope (should only be called once at program start)
    pub fn enterGlobalScope(self: *SymbolTable) !void {
        try self.scope_stack.enterScope(.global);
    }

    /// Enter a new function scope
    pub fn enterFunctionScope(self: *SymbolTable) !void {
        try self.scope_stack.enterScope(.function);
    }

    /// Enter a new block scope (for loops, if statements, etc.)
    pub fn enterBlockScope(self: *SymbolTable) !void {
        try self.scope_stack.enterScope(.block);
    }

    /// Exit the current scope
    pub fn exitScope(self: *SymbolTable) void {
        self.scope_stack.exitScope();
    }

    /// Get current scope depth (0 = global, 1 = function, 2+ = nested blocks)
    pub fn currentDepth(self: *SymbolTable) usize {
        return self.scope_stack.depth();
    }

    // ============================================================================
    // Symbol Definition
    // ============================================================================

    /// Define a variable in the current scope
    /// Returns error.SymbolAlreadyDefined if a symbol with this name already exists in current scope
    pub fn defineVariable(
        self: *SymbolTable,
        name: []const u8,
        type_info: ast.Type,
        is_global: bool,
        is_mutable: bool,
        loc: ast.SourceLocation,
    ) !void {
        const symbol = scope.Symbol{
            .variable = .{
                .name = name,
                .type = type_info,
                .is_global = is_global,
                .is_mutable = is_mutable,
                .loc = loc,
            },
        };
        try self.scope_stack.define(symbol);
    }

    /// Define a function in the current scope
    /// Returns error.SymbolAlreadyDefined if a function with this name already exists in current scope
    pub fn defineFunction(
        self: *SymbolTable,
        name: []const u8,
        return_type: ast.Type,
        params: []const ast.Param,
        loc: ast.SourceLocation,
    ) !void {
        const symbol = scope.Symbol{
            .function = .{
                .name = name,
                .return_type = return_type,
                .params = params,
                .loc = loc,
            },
        };
        try self.scope_stack.define(symbol);
    }

    /// Define a type (class, union, or typedef) in the current scope
    /// Returns error.SymbolAlreadyDefined if a type with this name already exists in current scope
    pub fn defineType(
        self: *SymbolTable,
        name: []const u8,
        underlying_type: ast.Type,
        loc: ast.SourceLocation,
    ) !void {
        const symbol = scope.Symbol{
            .type_def = .{
                .name = name,
                .underlying_type = underlying_type,
                .loc = loc,
            },
        };
        try self.scope_stack.define(symbol);
    }

    // ============================================================================
    // Symbol Lookup
    // ============================================================================

    /// Look up a symbol by name, searching from current scope up to global scope
    /// Returns null if symbol not found
    pub fn lookupSymbol(self: *SymbolTable, name: []const u8) ?scope.Symbol {
        return self.scope_stack.lookup(name);
    }

    /// Look up a symbol only in the current scope (no parent scope search)
    /// Returns null if symbol not found in current scope
    pub fn lookupLocal(self: *SymbolTable, name: []const u8) ?scope.Symbol {
        return self.scope_stack.lookupLocal(name);
    }

    // ============================================================================
    // Validation Helpers
    // ============================================================================

    /// Check if a variable with the given name is defined (searches all scopes)
    pub fn isVariableDefined(self: *SymbolTable, name: []const u8) bool {
        if (self.lookupSymbol(name)) |symbol| {
            return symbol == .variable;
        }
        return false;
    }

    /// Check if a function with the given name is defined (searches all scopes)
    pub fn isFunctionDefined(self: *SymbolTable, name: []const u8) bool {
        if (self.lookupSymbol(name)) |symbol| {
            return symbol == .function;
        }
        return false;
    }

    /// Check if a type with the given name is defined (searches all scopes)
    pub fn isTypeDefined(self: *SymbolTable, name: []const u8) bool {
        if (self.lookupSymbol(name)) |symbol| {
            return symbol == .type_def;
        }
        return false;
    }

    /// Get variable information, returns null if not a variable or not found
    pub fn getVariable(self: *SymbolTable, name: []const u8) ?struct {
        name: []const u8,
        type: ast.Type,
        is_global: bool,
        is_mutable: bool,
        loc: ast.SourceLocation,
    } {
        if (self.lookupSymbol(name)) |symbol| {
            if (symbol == .variable) {
                return .{
                    .name = symbol.variable.name,
                    .type = symbol.variable.type,
                    .is_global = symbol.variable.is_global,
                    .is_mutable = symbol.variable.is_mutable,
                    .loc = symbol.variable.loc,
                };
            }
        }
        return null;
    }

    /// Get function information, returns null if not a function or not found
    pub fn getFunction(self: *SymbolTable, name: []const u8) ?struct {
        name: []const u8,
        return_type: ast.Type,
        params: []const ast.Param,
        loc: ast.SourceLocation,
    } {
        if (self.lookupSymbol(name)) |symbol| {
            if (symbol == .function) {
                return .{
                    .name = symbol.function.name,
                    .return_type = symbol.function.return_type,
                    .params = symbol.function.params,
                    .loc = symbol.function.loc,
                };
            }
        }
        return null;
    }

    /// Get type definition, returns null if not a type or not found
    pub fn getType(self: *SymbolTable, name: []const u8) ?struct {
        name: []const u8,
        underlying_type: ast.Type,
        loc: ast.SourceLocation,
    } {
        if (self.lookupSymbol(name)) |symbol| {
            if (symbol == .type_def) {
                return .{
                    .name = symbol.type_def.name,
                    .underlying_type = symbol.type_def.underlying_type,
                    .loc = symbol.type_def.loc,
                };
            }
        }
        return null;
    }

    /// Check if a symbol is mutable (only meaningful for variables)
    pub fn isMutable(self: *SymbolTable, name: []const u8) bool {
        if (self.getVariable(name)) |var_info| {
            return var_info.is_mutable;
        }
        return false;
    }

    /// Check if a symbol is global (only meaningful for variables)
    pub fn isGlobal(self: *SymbolTable, name: []const u8) bool {
        if (self.getVariable(name)) |var_info| {
            return var_info.is_global;
        }
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

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
