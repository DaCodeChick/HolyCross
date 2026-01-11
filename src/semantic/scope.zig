//! Scope management for the semantic analyzer
//!
//! Handles lexical scoping for HolyC programs:
//! - Global scope: Functions, global variables, type definitions
//! - Function scope: Function parameters and local variables
//! - Block scope: Variables declared in `{ }` blocks
//!
//! Features:
//! - Nested scope support
//! - Scope-aware symbol lookup (searches parent scopes)
//! - Shadow detection

const std = @import("std");
const ast = @import("../parser/ast.zig");
const symbol_module = @import("symbol.zig");

const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

// Re-export Symbol types for convenience
pub const Symbol = symbol_module.Symbol;
pub const VariableSymbol = symbol_module.VariableSymbol;
pub const FunctionSymbol = symbol_module.FunctionSymbol;
pub const TypeSymbol = symbol_module.TypeSymbol;

/// A single lexical scope
pub const Scope = struct {
    symbols: StringHashMap(Symbol),
    parent: ?*Scope,
    kind: ScopeKind,

    pub const ScopeKind = enum {
        global,
        function,
        block,
    };

    pub fn init(allocator: Allocator, kind: ScopeKind, parent: ?*Scope) Scope {
        return .{
            .symbols = StringHashMap(Symbol).init(allocator),
            .parent = parent,
            .kind = kind,
        };
    }

    pub fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }

    /// Define a symbol in this scope
    /// Returns error if symbol already exists
    pub fn define(self: *Scope, symbol: Symbol) !void {
        const name = symbol.getName();

        if (self.symbols.contains(name)) {
            return error.SymbolAlreadyDefined;
        }

        try self.symbols.put(name, symbol);
    }

    /// Look up a symbol in this scope only (no parent search)
    pub fn lookupLocal(self: *Scope, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }

    /// Look up a symbol in this scope and all parent scopes
    pub fn lookup(self: *Scope, name: []const u8) ?Symbol {
        // Try local scope first
        if (self.symbols.get(name)) |symbol| {
            return symbol;
        }

        // Try parent scope
        if (self.parent) |parent| {
            return parent.lookup(name);
        }

        return null;
    }

    /// Check if a symbol is defined in this scope (local only)
    pub fn isDefined(self: *Scope, name: []const u8) bool {
        return self.symbols.contains(name);
    }
};

/// Scope stack for managing nested scopes
pub const ScopeStack = struct {
    scopes: std.ArrayList(*Scope),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ScopeStack {
        return ScopeStack{
            .scopes = .{ .items = &[_]*Scope{}, .capacity = 0 },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ScopeStack) void {
        // Free all scopes
        for (self.scopes.items) |scope| {
            scope.deinit();
            self.allocator.destroy(scope);
        }
        self.scopes.deinit(self.allocator);
    }

    /// Enter a new scope
    pub fn enterScope(self: *ScopeStack, kind: Scope.ScopeKind) !void {
        const scope = try self.allocator.create(Scope);
        const parent = self.getCurrentScope();
        scope.* = Scope.init(self.allocator, kind, parent);
        try self.scopes.append(self.allocator, scope);
    }

    /// Exit the current scope
    pub fn exitScope(self: *ScopeStack) void {
        if (self.scopes.items.len == 0) return;
        const scope = self.scopes.pop() orelse return;
        scope.deinit();
        self.allocator.destroy(scope);
    }

    /// Get the current (innermost) scope
    pub fn getCurrentScope(self: *ScopeStack) ?*Scope {
        if (self.scopes.items.len == 0) return null;
        return self.scopes.items[self.scopes.items.len - 1];
    }

    /// Define a symbol in the current scope
    pub fn define(self: *ScopeStack, symbol: Symbol) !void {
        const scope = self.getCurrentScope() orelse return error.NoActiveScope;
        try scope.define(symbol);
    }

    /// Look up a symbol starting from the current scope
    pub fn lookup(self: *ScopeStack, name: []const u8) ?Symbol {
        const scope = self.getCurrentScope() orelse return null;
        return scope.lookup(name);
    }

    /// Look up a symbol only in the current scope (no parent search)
    pub fn lookupLocal(self: *ScopeStack, name: []const u8) ?Symbol {
        const scope = self.getCurrentScope() orelse return null;
        return scope.lookupLocal(name);
    }

    /// Check if a symbol is defined in the current scope (local only)
    pub fn isDefinedInCurrentScope(self: *ScopeStack, name: []const u8) bool {
        const scope = self.getCurrentScope() orelse return false;
        return scope.isDefined(name);
    }

    /// Get the current scope depth
    pub fn depth(self: *ScopeStack) usize {
        return self.scopes.items.len;
    }
};

// Import tests
test {
    _ = @import("scope_test.zig");
}
