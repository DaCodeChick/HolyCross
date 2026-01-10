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

// Import tests
test {
    _ = @import("symbol_table_test.zig");
}
