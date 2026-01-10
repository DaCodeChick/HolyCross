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

const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

/// Symbol stored in a scope
pub const Symbol = union(enum) {
    variable: struct {
        name: []const u8,
        type: ast.Type,
        is_global: bool,
        is_mutable: bool,
        loc: ast.SourceLocation,
    },
    function: struct {
        name: []const u8,
        return_type: ast.Type,
        params: []const ast.Param,
        loc: ast.SourceLocation,
    },
    type_def: struct {
        name: []const u8,
        underlying_type: ast.Type,
        loc: ast.SourceLocation,
    },

    /// Get the name of this symbol
    pub fn getName(self: Symbol) []const u8 {
        return switch (self) {
            .variable => |v| v.name,
            .function => |f| f.name,
            .type_def => |t| t.name,
        };
    }

    /// Get the source location of this symbol
    pub fn getLocation(self: Symbol) ast.SourceLocation {
        return switch (self) {
            .variable => |v| v.loc,
            .function => |f| f.loc,
            .type_def => |t| t.loc,
        };
    }
};

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
        return .{
            .scopes = .{},
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

// ============================================================================
// Tests
// ============================================================================

test "Scope: define and lookup local" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scope = Scope.init(allocator, .global, null);
    defer scope.deinit();

    // Define a variable
    const var_symbol = Symbol{
        .variable = .{
            .name = "x",
            .type = .i64,
            .is_global = true,
            .is_mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    try scope.define(var_symbol);

    // Lookup the variable
    const found = scope.lookupLocal("x");
    try testing.expect(found != null);
    try testing.expectEqualStrings("x", found.?.getName());
}

test "Scope: duplicate definition error" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scope = Scope.init(allocator, .global, null);
    defer scope.deinit();

    const var_symbol = Symbol{
        .variable = .{
            .name = "x",
            .type = .i64,
            .is_global = true,
            .is_mutable = true,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    try scope.define(var_symbol);

    // Try to define again - should error
    const result = scope.define(var_symbol);
    try testing.expectError(error.SymbolAlreadyDefined, result);
}

test "Scope: parent scope lookup" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parent scope
    var parent_scope = Scope.init(allocator, .global, null);
    defer parent_scope.deinit();

    const parent_var = Symbol{
        .variable = .{
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
        .variable = .{
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

test "ScopeStack: enter and exit scopes" {
    const testing = std.testing;
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
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = ScopeStack.init(allocator);
    defer stack.deinit();

    // Global scope
    try stack.enterScope(.global);
    try stack.define(Symbol{
        .variable = .{
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
        .variable = .{
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
        .variable = .{
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
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stack = ScopeStack.init(allocator);
    defer stack.deinit();

    // Global scope - define x as I64
    try stack.enterScope(.global);
    try stack.define(Symbol{
        .variable = .{
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
        .variable = .{
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
