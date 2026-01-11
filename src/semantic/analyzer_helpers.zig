//! Helper functions for the semantic analyzer
//!
//! This module contains utility functions extracted from the main analyzer
//! to reduce code duplication and improve maintainability.
//!
//! Note: These functions use 'anytype' for error list parameters to avoid
//! circular dependencies with analyzer.zig (which defines SemanticError).

const std = @import("std");
const ast = @import("../parser/ast.zig");
const symbol_table_module = @import("symbol_table.zig");
const type_checker_module = @import("type_checker.zig");

const Allocator = std.mem.Allocator;
const SymbolTable = symbol_table_module.SymbolTable;
const TypeChecker = type_checker_module.TypeChecker;

/// Infer expression type and propagate type checker errors to analyzer.
/// This helper consolidates the common pattern of calling inferExprType and
/// transferring any type checker errors to the analyzer's error list.
pub fn inferExprTypeOrPropagate(
    allocator: Allocator,
    type_checker: *TypeChecker,
    errors: anytype, // *std.ArrayList(SemanticError) from analyzer
    expr: ast.Expr,
) !ast.Type {
    return type_checker.inferExprType(expr) catch |err| {
        if (type_checker.errors.items.len > 0) {
            const type_err = type_checker.errors.items[type_checker.errors.items.len - 1];
            const msg = try allocator.dupe(u8, type_err.message);
            try errors.append(allocator, .{
                .kind = .type_mismatch,
                .message = msg,
                .loc = type_err.loc,
            });
        }
        return err;
    };
}

/// Resolve type through pointer dereference if arrow operator is used.
/// Returns the appropriate type for member access based on whether '.' or '->' was used.
pub fn resolveAccessType(
    allocator: Allocator,
    object_type: ast.Type,
    is_arrow: bool,
    loc: ast.SourceLocation,
    errors: anytype, // *std.ArrayList(SemanticError) from analyzer
) !ast.Type {
    if (!is_arrow) return object_type;

    return switch (object_type) {
        .pointer => |ptr_type| ptr_type.*,
        else => {
            const msg = try std.fmt.allocPrint(
                allocator,
                "Arrow operator requires pointer type, got '{s}'",
                .{@tagName(object_type)},
            );
            try errors.append(allocator, .{
                .kind = .type_mismatch,
                .message = msg,
                .loc = loc,
            });
            return error.SemanticError;
        },
    };
}

/// Find a member by name in a member list.
/// Returns the member if found, null otherwise.
pub fn findMember(members: []const ast.ClassMember, name: []const u8) ?ast.ClassMember {
    for (members) |member| {
        if (std.mem.eql(u8, member.name, name)) {
            return member;
        }
    }
    return null;
}

/// Look up a function symbol by name, reporting appropriate errors if not found or not callable.
pub fn lookupFunctionSymbol(
    allocator: Allocator,
    symbol_table: *SymbolTable,
    func_name: []const u8,
    loc: ast.SourceLocation,
    errors: anytype, // *std.ArrayList(SemanticError) from analyzer
) !symbol_table_module.FunctionSymbol {
    const symbol = symbol_table.lookupSymbol(func_name) orelse {
        const msg = try std.fmt.allocPrint(
            allocator,
            "Undeclared function '{s}'",
            .{func_name},
        );
        try errors.append(allocator, .{
            .kind = .undeclared_identifier,
            .message = msg,
            .loc = loc,
        });
        return error.SemanticError;
    };

    return switch (symbol) {
        .function => |f| f,
        else => {
            const msg = try std.fmt.allocPrint(
                allocator,
                "'{s}' is not a function",
                .{func_name},
            );
            try errors.append(allocator, .{
                .kind = .not_callable,
                .message = msg,
                .loc = loc,
            });
            return error.SemanticError;
        },
    };
}
