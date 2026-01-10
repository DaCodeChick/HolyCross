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

    pub fn init(allocator: Allocator) Analyzer {
        var sym_table = SymbolTable.init(allocator);
        return .{
            .allocator = allocator,
            .symbol_table = sym_table,
            .type_checker = TypeChecker.init(allocator, &sym_table),
            .errors = .{},
        };
    }

    pub fn deinit(self: *Analyzer) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
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
    // Statement Analysis (Stub for now)
    // ========================================================================

    /// Analyze a statement (placeholder)
    fn analyzeStatement(self: *Analyzer, stmt: ast.Stmt) AnalyzerError!void {
        _ = self;
        _ = stmt;
        // TODO: Implement statement analysis
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
    invalid_continue,
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
