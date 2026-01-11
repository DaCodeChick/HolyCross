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
const helpers = @import("analyzer_helpers.zig");

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
    gotos: std.ArrayList(struct { label: []const u8, loc: ast.SourceLocation }), // Track goto statements
    current_function_return_type: ?ast.Type, // Track current function's return type
    has_return_statement: bool, // Track if function has any return statements

    // Type information for member access validation
    class_members: std.StringHashMap([]ast.ClassMember), // Map class name to members
    union_members: std.StringHashMap([]ast.ClassMember), // Map union name to members

    pub fn init(allocator: Allocator) Analyzer {
        var sym_table = SymbolTable.init(allocator);
        return .{
            .allocator = allocator,
            .symbol_table = sym_table,
            .type_checker = TypeChecker.init(allocator, &sym_table),
            .errors = .{},
            .loop_depth = 0,
            .labels = std.StringHashMap(ast.SourceLocation).init(allocator),
            .gotos = .{},
            .current_function_return_type = null,
            .has_return_statement = false,
            .class_members = std.StringHashMap([]ast.ClassMember).init(allocator),
            .union_members = std.StringHashMap([]ast.ClassMember).init(allocator),
        };
    }

    pub fn deinit(self: *Analyzer) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
        self.gotos.deinit(self.allocator);
        self.labels.deinit();
        self.class_members.deinit();
        self.union_members.deinit();
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

    /// Collect a composite type declaration (class or union).
    /// This unified function handles both class and union declarations to avoid duplication.
    fn collectCompositeTypeDeclaration(
        self: *Analyzer,
        name: []const u8,
        members: []ast.ClassMember,
        repr_type: ?ast.Type,
        loc: ast.SourceLocation,
        type_kind: enum { class, union_type },
    ) AnalyzerError!void {
        const kind_str = if (type_kind == .class) "class" else "union";

        // Check for duplicate declaration
        if (self.symbol_table.lookupLocal(name)) |existing| {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Redeclaration of {s} '{s}' (previously declared at line {d})",
                .{ kind_str, name, existing.getLocation().line },
            );
            try self.addError(.redeclared_identifier, msg, loc);
            return;
        }

        // Check for duplicate member names within the composite type
        var seen_members = std.StringHashMap(void).init(self.allocator);
        defer seen_members.deinit();

        for (members) |member| {
            if (seen_members.contains(member.name)) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Duplicate member '{s}' in {s} '{s}'",
                    .{ member.name, kind_str, name },
                );
                try self.addError(.redeclared_identifier, msg, member.loc);
            } else {
                try seen_members.put(member.name, {});
            }
        }

        // Store member information in the appropriate map
        const members_map = if (type_kind == .class) &self.class_members else &self.union_members;
        try members_map.put(name, members);

        // Define as a type (use repr_type if present, otherwise a named type)
        const underlying_type = if (repr_type) |rt| rt else ast.Type{ .named = name };
        try self.symbol_table.defineType(name, underlying_type, loc);
    }

    /// Collect class declaration
    fn collectClassDeclaration(self: *Analyzer, cls: anytype) AnalyzerError!void {
        try self.collectCompositeTypeDeclaration(
            cls.name,
            cls.members,
            cls.repr_type,
            cls.loc,
            .class,
        );
    }

    /// Collect union declaration
    fn collectUnionDeclaration(self: *Analyzer, uni: anytype) AnalyzerError!void {
        try self.collectCompositeTypeDeclaration(
            uni.name,
            uni.members,
            uni.repr_type,
            uni.loc,
            .union_type,
        );
    }

    /// Collect global variable declaration
    fn collectGlobalVariableDeclaration(self: *Analyzer, gvar: anytype) AnalyzerError!void {
        // Check for duplicate global variable
        if (self.symbol_table.lookupLocal(gvar.name)) |existing| {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Redeclaration of global variable '{s}' (previously declared at line {d})",
                .{ gvar.name, existing.getLocation().line },
            );
            try self.addError(.redeclared_identifier, msg, gvar.loc);
            return;
        }

        // If there's an initializer, validate its type
        if (gvar.init) |init_expr| {
            const init_type = try self.inferExprTypeOrPropagate(init_expr);

            // Check type compatibility
            const compatible = try self.type_checker.areTypesCompatible(init_type, gvar.type);
            if (!compatible) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Cannot initialize global variable of type '{s}' with value of type '{s}'",
                    .{ @tagName(gvar.type), @tagName(init_type) },
                );
                try self.addError(.type_mismatch, msg, gvar.loc);
            }
        }

        // Define global variable in symbol table
        try self.symbol_table.defineVariable(
            gvar.name,
            gvar.type,
            true, // is global
            true, // mutable
            gvar.loc,
        );
    }

    /// Collect import declaration (placeholder)
    fn collectImportDeclaration(self: *Analyzer, imp: anytype) AnalyzerError!void {
        _ = self;
        _ = imp;
        // TODO: Implement import declaration collection
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

    /// Infer expression type and propagate type checker errors to analyzer
    fn inferExprTypeOrPropagate(self: *Analyzer, expr: ast.Expr) !ast.Type {
        return helpers.inferExprTypeOrPropagate(
            self.allocator,
            &self.type_checker,
            &self.errors,
            expr,
        );
    }

    /// Resolve type through pointer dereference if arrow operator is used
    fn resolveAccessType(
        self: *Analyzer,
        object_type: ast.Type,
        is_arrow: bool,
        loc: ast.SourceLocation,
    ) !ast.Type {
        return helpers.resolveAccessType(
            self.allocator,
            object_type,
            is_arrow,
            loc,
            &self.errors,
        );
    }

    /// Look up a function symbol by name
    fn lookupFunctionSymbol(
        self: *Analyzer,
        func_name: []const u8,
        loc: ast.SourceLocation,
    ) !symbol_table.FunctionSymbol {
        return helpers.lookupFunctionSymbol(
            self.allocator,
            &self.symbol_table,
            func_name,
            loc,
            &self.errors,
        );
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
        self.has_return_statement = false;
        self.labels.clearRetainingCapacity();
        self.gotos.clearRetainingCapacity();

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

        // Validate all goto targets exist
        for (self.gotos.items) |goto_info| {
            if (!self.labels.contains(goto_info.label)) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Undefined label '{s}' used in goto",
                    .{goto_info.label},
                );
                try self.addError(.undefined_label, msg, goto_info.loc);
            }
        }

        // Check if non-void function is missing return statement
        if (func.return_type != .u0 and !self.has_return_statement) {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Function '{s}' with return type '{s}' is missing return statement",
                .{ func.name, @tagName(func.return_type) },
            );
            try self.addError(.missing_return, msg, func.loc);
        }
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
        // Validate the expression (this includes function call validation)
        try self.validateExpression(expr);

        // Also infer the expression type
        _ = try self.inferExprTypeOrPropagate(expr);
    }

    /// Validate an expression (recursively validate function calls)
    fn validateExpression(self: *Analyzer, expr: ast.Expr) AnalyzerError!void {
        switch (expr) {
            .integer, .float, .string, .char, .identifier => {}, // Primitives are fine

            .binary => |bin| {
                try self.validateExpression(bin.left.*);
                try self.validateExpression(bin.right.*);
            },

            .unary => |un| {
                try self.validateExpression(un.operand.*);
            },

            .call => |call| {
                // Validate callee
                try self.validateExpression(call.callee.*);

                // Validate arguments
                for (call.args) |arg| {
                    try self.validateExpression(arg);
                }

                // Validate function call
                try self.validateFunctionCall(call.callee.*, call.args, expr.getLocation());
            },

            .subscript => |sub| {
                try self.validateExpression(sub.array.*);
                try self.validateExpression(sub.index.*);
            },

            .member => |mem| {
                try self.validateExpression(mem.object.*);
                // Validate member access
                try self.validateMemberAccess(mem.object.*, mem.member, expr.getLocation(), false);
            },

            .arrow => |arr| {
                try self.validateExpression(arr.object.*);
                // Validate member access (arrow is for pointer dereferencing)
                try self.validateMemberAccess(arr.object.*, arr.member, expr.getLocation(), true);
            },

            .cast => |c| {
                try self.validateExpression(c.expr.*);
            },

            .sizeof_expr => |se| {
                try self.validateExpression(se.expr.*);
            },

            .sizeof_type, .offset => {}, // Type operations don't need validation
        }
    }

    /// Validate a function call
    fn validateFunctionCall(self: *Analyzer, callee: ast.Expr, args: []const ast.Expr, loc: ast.SourceLocation) AnalyzerError!void {
        // Get the function name if it's an identifier
        const func_name = switch (callee) {
            .identifier => |id| id.name,
            else => return, // Complex callees (function pointers) are not validated yet
        };

        // Look up the function symbol
        const func_symbol = try self.lookupFunctionSymbol(func_name, loc);

        // Check argument count
        if (args.len != func_symbol.params.len) {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Function '{s}' expects {d} argument(s), but got {d}",
                .{ func_name, func_symbol.params.len, args.len },
            );
            try self.addError(.argument_count_mismatch, msg, loc);
            return;
        }

        // Check argument types
        for (args, func_symbol.params, 0..) |arg, param, i| {
            const arg_type = try self.inferExprTypeOrPropagate(arg);

            const compatible = try self.type_checker.areTypesCompatible(arg_type, param.type);
            if (!compatible) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Argument {d} to function '{s}': expected type '{s}', got '{s}'",
                    .{ i + 1, func_name, @tagName(param.type), @tagName(arg_type) },
                );
                try self.addError(.argument_type_mismatch, msg, loc);
            }
        }
    }

    /// Validate member access on a class or union
    fn validateMemberAccess(
        self: *Analyzer,
        object: ast.Expr,
        member_name: []const u8,
        loc: ast.SourceLocation,
        is_arrow: bool,
    ) AnalyzerError!void {
        // Infer the type of the object
        var object_type = self.type_checker.inferExprType(object) catch |err| {
            // If type inference fails, skip member validation
            return err;
        };

        // Resolve type (dereference if arrow operator used)
        object_type = try self.resolveAccessType(object_type, is_arrow, loc);

        // Check if object_type is a named type (class or union)
        const type_name = switch (object_type) {
            .named => |name| name,
            else => {
                // Not a class or union, can't validate members
                // (Could be built-in type with members we don't track)
                return;
            },
        };

        // Look up members in class_members or union_members
        const members = self.class_members.get(type_name) orelse
            self.union_members.get(type_name) orelse {
            // Type not found in our maps - might be an undefined type
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Unknown type '{s}'",
                .{type_name},
            );
            try self.addError(.undeclared_identifier, msg, loc);
            return;
        };

        // Check if member exists
        if (helpers.findMember(members, member_name) == null) {
            const msg = try std.fmt.allocPrint(
                self.allocator,
                "Type '{s}' has no member named '{s}'",
                .{ type_name, member_name },
            );
            try self.addError(.undeclared_identifier, msg, loc);
        }
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
            const init_type = try self.inferExprTypeOrPropagate(init_expr);

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
        var found_terminator = false; // Track if we hit return/break
        for (stmts, 0..) |stmt, i| {
            // Check if previous statement was a terminator
            if (found_terminator) {
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Unreachable code after {s} statement",
                    .{if (i > 0) switch (stmts[i - 1]) {
                        .return_stmt => "return",
                        .break_stmt => "break",
                        else => "control flow",
                    } else "control flow"},
                );
                try self.addError(.unreachable_code, msg, stmt.getLocation());
                // Continue analyzing anyway for better error reporting
            }

            try self.analyzeStatement(stmt);

            // Mark if this statement is a terminator
            switch (stmt) {
                .return_stmt, .break_stmt => {
                    found_terminator = true;
                },
                else => {},
            }
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
        _ = try self.inferExprTypeOrPropagate(condition);

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
        _ = try self.inferExprTypeOrPropagate(condition);

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
        _ = try self.inferExprTypeOrPropagate(condition);
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
            _ = try self.inferExprTypeOrPropagate(cond);
        }

        // Analyze increment
        if (increment) |incr| {
            _ = try self.inferExprTypeOrPropagate(incr);
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
        _ = try self.inferExprTypeOrPropagate(expr);

        // Enter loop context (switch supports break)
        self.loop_depth += 1;
        defer self.loop_depth -= 1;

        // Analyze each case
        for (cases) |case| {
            // Analyze case value if present (not default)
            if (case.value) |val| {
                _ = try self.inferExprTypeOrPropagate(val);
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
            const ret_type = try self.inferExprTypeOrPropagate(ret_expr);

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

        // Mark that function has a return statement
        self.has_return_statement = true;
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
        // Record this goto for later validation
        try self.gotos.append(self.allocator, .{ .label = label, .loc = loc });
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

    /// Add a semantic error (takes ownership of the message)
    fn addError(self: *Analyzer, kind: ErrorKind, message: []const u8, loc: ast.SourceLocation) AnalyzerError!void {
        try self.errors.append(self.allocator, .{
            .kind = kind,
            .message = message, // Take ownership - caller must allocate
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
