//! High-level symbol table API for semantic analysis
//!
//! Provides a convenient wrapper around ScopeStack with methods for:
//! - Defining variables, functions, and types
//! - Looking up symbols with type-specific helpers
//! - Validating symbol properties (mutability, scope, etc.)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../parser/ast.zig");
const scope = @import("scope.zig");
const symbol_module = @import("symbol.zig");

// Re-export symbol types for convenience
pub const Symbol = symbol_module.Symbol;
pub const VariableSymbol = symbol_module.VariableSymbol;
pub const FunctionSymbol = symbol_module.FunctionSymbol;
pub const TypeSymbol = symbol_module.TypeSymbol;

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
            .variable = VariableSymbol{
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
        is_extern: bool,
    ) !void {
        const symbol = scope.Symbol{
            .function = FunctionSymbol{
                .name = name,
                .return_type = return_type,
                .params = params,
                .loc = loc,
                .is_extern = is_extern,
            },
        };
        try self.scope_stack.define(symbol);
    }

    /// Update an existing function in the current scope (e.g., replacing extern with definition)
    /// Returns error.SymbolNotDefined if the function doesn't exist
    pub fn updateFunction(
        self: *SymbolTable,
        name: []const u8,
        return_type: ast.Type,
        params: []const ast.Param,
        loc: ast.SourceLocation,
        is_extern: bool,
    ) !void {
        const symbol = scope.Symbol{
            .function = FunctionSymbol{
                .name = name,
                .return_type = return_type,
                .params = params,
                .loc = loc,
                .is_extern = is_extern,
            },
        };
        try self.scope_stack.update(symbol);
    }

    /// Define a type (class, union, or typedef) in the current scope
    /// Returns error.SymbolAlreadyDefined if a type with this name already exists in current scope
    pub fn defineType(
        self: *SymbolTable,
        name: []const u8,
        underlying_type: ast.Type,
        loc: ast.SourceLocation,
        is_extern: bool,
    ) !void {
        const symbol = scope.Symbol{
            .type_def = TypeSymbol{
                .name = name,
                .underlying_type = underlying_type,
                .loc = loc,
                .is_extern = is_extern,
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
    pub fn getVariable(self: *SymbolTable, name: []const u8) ?VariableSymbol {
        if (self.lookupSymbol(name)) |symbol| {
            if (symbol == .variable) {
                return symbol.variable;
            }
        }
        return null;
    }

    /// Get function information, returns null if not a function or not found
    pub fn getFunction(self: *SymbolTable, name: []const u8) ?FunctionSymbol {
        if (self.lookupSymbol(name)) |symbol| {
            if (symbol == .function) {
                return symbol.function;
            }
        }
        return null;
    }

    /// Get type definition, returns null if not a type or not found
    pub fn getType(self: *SymbolTable, name: []const u8) ?TypeSymbol {
        if (self.lookupSymbol(name)) |symbol| {
            if (symbol == .type_def) {
                return symbol.type_def;
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
    _ = @import("tests/symbol_table_tests.zig");
}
