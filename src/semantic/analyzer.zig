//! Main semantic analyzer for HolyCross
//!
//! Orchestrates semantic analysis in two passes:
//! Pass 1: Collect all declarations (functions, globals, types)
//! Pass 2: Analyze function bodies and validate statements
//!
//! This module coordinates:
//! - Symbol table management
//! - Type checking
//! - Scope resolution
//! - Error collection and reporting

const std = @import("std");
const ast = @import("../parser/ast.zig");
const symbol_table = @import("symbol_table.zig");
const type_checker = @import("type_checker.zig");

const Allocator = std.mem.Allocator;
const SymbolTable = symbol_table.SymbolTable;
const TypeChecker = type_checker.TypeChecker;

/// Main semantic analyzer
pub const Analyzer = struct {
    allocator: Allocator,
    symbol_table: SymbolTable,
    type_checker: TypeChecker,
    errors: std.ArrayList(SemanticError),

    // Context tracking for validation
    loop_depth: u32, // Track nested loop depth for break statements
    labels: std.StringHashMap(ast.SourceLocation), // Track labels for goto
    current_function_return_type: ?ast.Type, // Track current function's return type

    pub fn init(allocator: Allocator) Analyzer {
        var sym_table = SymbolTable.init(allocator);
        return .{
            .allocator = allocator,
            .symbol_table = sym_table,
            .type_checker = TypeChecker.init(allocator, &sym_table),
            .errors = .{},
            .loop_depth = 0,
            .labels = std.StringHashMap(ast.SourceLocation).init(allocator),
            .current_function_return_type = null,
        };
    }

    pub fn deinit(self: *Analyzer) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
        self.labels.deinit();
        self.type_checker.deinit();
        self.symbol_table.deinit();
    }

    /// Analyze a complete program (two-pass analysis)
    pub fn analyze(self: *Analyzer, program: ast.Program) AnalyzerError!void {
        // Enter global scope
        try self.symbol_table.enterGlobalScope();

        // Pass 1: Collect all declarations
        try self.collectDeclarations(program.decls);

        // Pass 2: Analyze function bodies
        try self.analyzeFunctionBodies(program.decls);

        // Check if any errors were collected
        if (self.errors.items.len > 0) {
            return error.SemanticError;
        }
    }

    // ========================================================================
    // Pass 1: Declaration Collection
    // ========================================================================

    /// Collect all top-level declarations (functions, classes, unions, global vars)
    fn collectDeclarations(self: *Analyzer, decls: []const ast.Decl) AnalyzerError!void {
        for (decls) |decl| {
            try self.collectDeclaration(decl);
        }
    }

    /// Collect a single declaration
    fn collectDeclaration(self: *Analyzer, decl: ast.Decl) AnalyzerError!void {
        switch (decl) {
            .function => |func| try self.collectFunctionDeclaration(func),
            .class => |cls| try self.collectClassDeclaration(cls),
            .union_decl => |uni| try self.collectUnionDeclaration(uni),
            .global_var => |gvar| try self.collectGlobalVariableDeclaration(gvar),
            .import => |imp| try self.collectImportDeclaration(imp),
            .preprocessor => {}, // Skip preprocessor directives
        }
    }

    /// Collect function declaration
    fn collectFunctionDeclaration(self: *Analyzer, func: anytype) AnalyzerError!void {
        // Check for duplicate function
        if (self.symbol_table.lookupLocal(func.name)) |existing| {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Redeclaration of function '{s}' (previously declared at line {d})",
                .{ func.name, existing.getLocation().line },
            );
            try self.addError(.redeclared_identifier, msg, func.loc);
            return;
        }

        // Define function in symbol table
        try self.symbol_table.defineFunction(
            func.name,
            func.return_type,
            func.params,
            func.loc,
        );
    }

    /// Collect class declaration (placeholder)
    fn collectClassDeclaration(self: *Analyzer, cls: anytype) AnalyzerError!void {
        _ = self;
        _ = cls;
        // TODO: Implement class declaration collection
    }

    /// Collect union declaration (placeholder)
    fn collectUnionDeclaration(self: *Analyzer, uni: anytype) AnalyzerError!void {
        _ = self;
        _ = uni;
        // TODO: Implement union declaration collection
    }

    /// Collect global variable declaration (placeholder)
    fn collectGlobalVariableDeclaration(self: *Analyzer, gvar: anytype) AnalyzerError!void {
        _ = self;
        _ = gvar;
        // TODO: Implement global variable declaration collection
    }

    /// Collect enum declaration (placeholder)
    fn collectImportDeclaration(self: *Analyzer, imp: anytype) AnalyzerError!void {
        _ = self;
        _ = imp;
        // TODO: Implement import declaration collection
    }

    // ========================================================================
    // Pass 2: Function Body Analysis
    // ========================================================================

    /// Analyze all function bodies
    fn analyzeFunctionBodies(self: *Analyzer, decls: []const ast.Decl) AnalyzerError!void {
        for (decls) |decl| {
            switch (decl) {
                .function => |func| {
                    // Only analyze functions with bodies (not forward declarations)
                    if (func.body) |body| {
                        try self.analyzeFunctionBody(func, body);
                    }
                },
                else => {}, // Other declarations don't have bodies to analyze
            }
        }
    }

    /// Analyze a single function body
    fn analyzeFunctionBody(self: *Analyzer, func: anytype, body: ast.Stmt) AnalyzerError!void {
        // Enter function scope
        try self.symbol_table.enterFunctionScope();
        defer self.symbol_table.exitScope();

        // Reset function context
        self.current_function_return_type = func.return_type;
        self.loop_depth = 0;
        self.labels.clearRetainingCapacity();

        // Add function parameters to scope
        for (func.params) |param| {
            // Check for duplicate parameter names
            if (self.symbol_table.lookupLocal(param.name)) |_| {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Duplicate parameter name '{s}'",
                    .{param.name},
                );
                try self.addError(.redeclared_identifier, msg, param.loc);
                continue;
            }

            try self.symbol_table.defineVariable(
                param.name,
                param.type,
                false, // not global
                true, // mutable (parameters are mutable by default)
                param.loc,
            );
        }

        // Analyze function body statement
        try self.analyzeStatement(body);
    }

    // ========================================================================
    // Statement Analysis
    // ========================================================================

    /// Analyze a statement
    fn analyzeStatement(self: *Analyzer, stmt: ast.Stmt) AnalyzerError!void {
        switch (stmt) {
            .empty => {}, // Nothing to analyze
            .expr => |e| try self.analyzeExpressionStatement(e.expr),
            .var_decl => |v| try self.analyzeVariableDeclaration(v.type, v.name, v.init, v.loc),
            .block => |b| try self.analyzeBlock(b.stmts),
            .if_stmt => |i| try self.analyzeIfStatement(i.condition, i.then_stmt.*, i.else_stmt),
            .while_stmt => |w| try self.analyzeWhileStatement(w.condition, w.body.*),
            .do_while => |d| try self.analyzeDoWhileStatement(d.body.*, d.condition),
            .for_stmt => |f| try self.analyzeForStatement(f.init, f.condition, f.increment, f.body.*),
            .switch_stmt => |s| try self.analyzeSwitchStatement(s.expr, s.cases),
            .return_stmt => |r| try self.analyzeReturnStatement(r.expr, r.loc),
            .break_stmt => |b| try self.analyzeBreakStatement(b.loc),
            .goto_stmt => |g| try self.analyzeGotoStatement(g.label, g.loc),
            .label => |l| try self.analyzeLabel(l.name, l.loc),
            .try_catch => |tc| try self.analyzeTryCatch(tc.try_block.*, tc.catch_block.*),
            .asm_block => {}, // Skip inline assembly (no semantic analysis needed)
        }
    }

    /// Analyze expression statement
    fn analyzeExpressionStatement(self: *Analyzer, expr: ast.Expr) AnalyzerError!void {
        // Just infer the expression type (this validates it)
        _ = self.type_checker.inferExprType(expr) catch |err| {
            // Convert type checker errors to analyzer errors
            if (self.type_checker.errors.items.len > 0) {
                const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                const msg = try self.allocator.dupe(u8, type_err.message);
                try self.errors.append(self.allocator, .{
                    .kind = .type_mismatch,
                    .message = msg,
                    .loc = type_err.loc,
                });
            }
            return err;
        };
    }

    /// Analyze variable declaration
    fn analyzeVariableDeclaration(
        self: *Analyzer,
        var_type: ast.Type,
        name: []const u8,
        initializer: ?ast.Expr,
        loc: ast.SourceLocation,
    ) AnalyzerError!void {
        // Check for duplicate variable in current scope
        if (self.symbol_table.lookupLocal(name)) |_| {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Redeclaration of variable '{s}'",
                .{name},
            );
            try self.addError(.redeclared_identifier, msg, loc);
            return;
        }

        // If there's an initializer, check type compatibility
        if (initializer) |init_expr| {
            const init_type = self.type_checker.inferExprType(init_expr) catch |err| {
                if (self.type_checker.errors.items.len > 0) {
                    const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                    const msg = try self.allocator.dupe(u8, type_err.message);
                    try self.errors.append(self.allocator, .{
                        .kind = .type_mismatch,
                        .message = msg,
                        .loc = type_err.loc,
                    });
                }
                return err;
            };

            // Check type compatibility
            const compatible = try self.type_checker.areTypesCompatible(init_type, var_type);
            if (!compatible) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Cannot initialize variable of type '{s}' with value of type '{s}'",
                    .{ @tagName(var_type), @tagName(init_type) },
                );
                try self.addError(.type_mismatch, msg, loc);
            }
        }

        // Define variable in symbol table
        try self.symbol_table.defineVariable(
            name,
            var_type,
            false, // not global (we're in function scope)
            true, // mutable
            loc,
        );
    }

    /// Analyze block statement
    fn analyzeBlock(self: *Analyzer, stmts: []const ast.Stmt) AnalyzerError!void {
        // Enter new block scope
        try self.symbol_table.enterBlockScope();
        defer self.symbol_table.exitScope();

        // Analyze each statement in the block
        for (stmts) |stmt| {
            try self.analyzeStatement(stmt);
        }
    }

    /// Analyze if statement
    fn analyzeIfStatement(
        self: *Analyzer,
        condition: ast.Expr,
        then_stmt: ast.Stmt,
        else_stmt: ?*ast.Stmt,
    ) AnalyzerError!void {
        // Analyze condition
        _ = self.type_checker.inferExprType(condition) catch |err| {
            if (self.type_checker.errors.items.len > 0) {
                const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                const msg = try self.allocator.dupe(u8, type_err.message);
                try self.errors.append(self.allocator, .{
                    .kind = .type_mismatch,
                    .message = msg,
                    .loc = type_err.loc,
                });
            }
            return err;
        };

        // Analyze then branch
        try self.analyzeStatement(then_stmt);

        // Analyze else branch if present
        if (else_stmt) |else_s| {
            try self.analyzeStatement(else_s.*);
        }
    }

    /// Analyze while statement
    fn analyzeWhileStatement(self: *Analyzer, condition: ast.Expr, body: ast.Stmt) AnalyzerError!void {
        // Analyze condition
        _ = self.type_checker.inferExprType(condition) catch |err| {
            if (self.type_checker.errors.items.len > 0) {
                const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                const msg = try self.allocator.dupe(u8, type_err.message);
                try self.errors.append(self.allocator, .{
                    .kind = .type_mismatch,
                    .message = msg,
                    .loc = type_err.loc,
                });
            }
            return err;
        };

        // Enter loop context
        self.loop_depth += 1;
        defer self.loop_depth -= 1;

        // Analyze body
        try self.analyzeStatement(body);
    }

    /// Analyze do-while statement
    fn analyzeDoWhileStatement(self: *Analyzer, body: ast.Stmt, condition: ast.Expr) AnalyzerError!void {
        // Enter loop context
        self.loop_depth += 1;
        defer self.loop_depth -= 1;

        // Analyze body
        try self.analyzeStatement(body);

        // Analyze condition
        _ = self.type_checker.inferExprType(condition) catch |err| {
            if (self.type_checker.errors.items.len > 0) {
                const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                const msg = try self.allocator.dupe(u8, type_err.message);
                try self.errors.append(self.allocator, .{
                    .kind = .type_mismatch,
                    .message = msg,
                    .loc = type_err.loc,
                });
            }
            return err;
        };
    }

    /// Analyze for statement
    fn analyzeForStatement(
        self: *Analyzer,
        init_stmt: ?*ast.Stmt,
        condition: ?ast.Expr,
        increment: ?ast.Expr,
        body: ast.Stmt,
    ) AnalyzerError!void {
        // For loop creates its own scope for the init statement
        try self.symbol_table.enterBlockScope();
        defer self.symbol_table.exitScope();

        // Analyze init
        if (init_stmt) |init_s| {
            try self.analyzeStatement(init_s.*);
        }

        // Analyze condition
        if (condition) |cond| {
            _ = self.type_checker.inferExprType(cond) catch |err| {
                if (self.type_checker.errors.items.len > 0) {
                    const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                    const msg = try self.allocator.dupe(u8, type_err.message);
                    try self.errors.append(self.allocator, .{
                        .kind = .type_mismatch,
                        .message = msg,
                        .loc = type_err.loc,
                    });
                }
                return err;
            };
        }

        // Analyze increment
        if (increment) |incr| {
            _ = self.type_checker.inferExprType(incr) catch |err| {
                if (self.type_checker.errors.items.len > 0) {
                    const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                    const msg = try self.allocator.dupe(u8, type_err.message);
                    try self.errors.append(self.allocator, .{
                        .kind = .type_mismatch,
                        .message = msg,
                        .loc = type_err.loc,
                    });
                }
                return err;
            };
        }

        // Enter loop context
        self.loop_depth += 1;
        defer self.loop_depth -= 1;

        // Analyze body
        try self.analyzeStatement(body);
    }

    /// Analyze switch statement
    fn analyzeSwitchStatement(self: *Analyzer, expr: ast.Expr, cases: []const ast.SwitchCase) AnalyzerError!void {
        // Analyze switch expression
        _ = self.type_checker.inferExprType(expr) catch |err| {
            if (self.type_checker.errors.items.len > 0) {
                const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                const msg = try self.allocator.dupe(u8, type_err.message);
                try self.errors.append(self.allocator, .{
                    .kind = .type_mismatch,
                    .message = msg,
                    .loc = type_err.loc,
                });
            }
            return err;
        };

        // Enter loop context (switch supports break)
        self.loop_depth += 1;
        defer self.loop_depth -= 1;

        // Analyze each case
        for (cases) |case| {
            // Analyze case value if present (not default)
            if (case.value) |val| {
                _ = self.type_checker.inferExprType(val) catch |err| {
                    if (self.type_checker.errors.items.len > 0) {
                        const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                        const msg = try self.allocator.dupe(u8, type_err.message);
                        try self.errors.append(self.allocator, .{
                            .kind = .type_mismatch,
                            .message = msg,
                            .loc = type_err.loc,
                        });
                    }
                    return err;
                };
            }

            // Analyze case statements
            for (case.stmts) |stmt| {
                try self.analyzeStatement(stmt);
            }
        }
    }

    /// Analyze return statement
    fn analyzeReturnStatement(self: *Analyzer, expr: ?ast.Expr, loc: ast.SourceLocation) AnalyzerError!void {
        const expected_type = self.current_function_return_type orelse {
            const msg = try self.allocator.dupe(u8, "Return statement outside of function");
            try self.addError(.invalid_return, msg, loc);
            return;
        };

        // Check if we have a return value
        if (expr) |ret_expr| {
            // Infer return expression type
            const ret_type = self.type_checker.inferExprType(ret_expr) catch |err| {
                if (self.type_checker.errors.items.len > 0) {
                    const type_err = self.type_checker.errors.items[self.type_checker.errors.items.len - 1];
                    const msg = try self.allocator.dupe(u8, type_err.message);
                    try self.errors.append(self.allocator, .{
                        .kind = .type_mismatch,
                        .message = msg,
                        .loc = type_err.loc,
                    });
                }
                return err;
            };

            // Check type compatibility
            const compatible = try self.type_checker.areTypesCompatible(ret_type, expected_type);
            if (!compatible) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Return type '{s}' does not match function return type '{s}'",
                    .{ @tagName(ret_type), @tagName(expected_type) },
                );
                try self.addError(.type_mismatch, msg, loc);
            }
        } else {
            // No return value - check if function expects U0 (void)
            if (expected_type != .u0) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Function expects return type '{s}' but got no return value",
                    .{@tagName(expected_type)},
                );
                try self.addError(.invalid_return, msg, loc);
            }
        }
    }

    /// Analyze break statement
    fn analyzeBreakStatement(self: *Analyzer, loc: ast.SourceLocation) AnalyzerError!void {
        if (self.loop_depth == 0) {
            const msg = try self.allocator.dupe(u8, "Break statement outside of loop or switch");
            try self.addError(.invalid_break, msg, loc);
        }
    }

    /// Analyze goto statement
    fn analyzeGotoStatement(self: *Analyzer, label: []const u8, loc: ast.SourceLocation) AnalyzerError!void {
        // We'll validate goto targets in a second pass if needed
        // For now, just record that we saw a goto
        _ = self;
        _ = label;
        _ = loc;
        // TODO: Implement goto validation
    }

    /// Analyze label
    fn analyzeLabel(self: *Analyzer, name: []const u8, loc: ast.SourceLocation) AnalyzerError!void {
        // Check for duplicate label
        if (self.labels.get(name)) |existing_loc| {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Duplicate label '{s}' (previously defined at line {d})",
                .{ name, existing_loc.line },
            );
            try self.addError(.duplicate_label, msg, loc);
            return;
        }

        // Register label
        try self.labels.put(name, loc);
    }

    /// Analyze try-catch statement
    fn analyzeTryCatch(self: *Analyzer, try_block: ast.Stmt, catch_block: ast.Stmt) AnalyzerError!void {
        // Analyze try block
        try self.analyzeStatement(try_block);

        // Analyze catch block
        try self.analyzeStatement(catch_block);
    }

    // ========================================================================
    // Error Management
    // ========================================================================

    /// Add a semantic error
    fn addError(self: *Analyzer, kind: ErrorKind, message: []const u8, loc: ast.SourceLocation) AnalyzerError!void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.errors.append(self.allocator, .{
            .kind = kind,
            .message = owned_message,
            .loc = loc,
        });
    }

    /// Get all collected errors
    pub fn getErrors(self: *Analyzer) []const SemanticError {
        return self.errors.items;
    }
};

// ============================================================================
// Error Definitions
// ============================================================================

/// Error set for analyzer operations
pub const AnalyzerError = error{
    SemanticError,
    OutOfMemory,
    NoActiveScope,
    SymbolAlreadyDefined,
    TypeError,
};

/// Semantic error information
pub const SemanticError = struct {
    kind: ErrorKind,
    message: []const u8, // Owned, must be freed
    loc: ast.SourceLocation,
};

/// Kinds of semantic errors
pub const ErrorKind = enum {
    undeclared_identifier,
    redeclared_identifier,
    type_mismatch,
    invalid_operation,
    invalid_cast,
    invalid_subscript,
    not_callable,
    argument_count_mismatch,
    argument_type_mismatch,
    invalid_break,
    invalid_return,
    undefined_label,
    duplicate_label,
    missing_return,
    unreachable_code,
};

// Import tests
test {
    _ = @import("analyzer_test.zig");
}
