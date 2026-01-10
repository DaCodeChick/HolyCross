//! Symbol definitions for the semantic analyzer
//!
//! This module defines the Symbol union type which represents
//! variables, functions, and type definitions in the symbol table.

const std = @import("std");
const ast = @import("../parser/ast.zig");

/// Symbol stored in a scope
pub const Symbol = union(enum) {
    variable: VariableSymbol,
    function: FunctionSymbol,
    type_def: TypeSymbol,

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

/// Variable symbol information
pub const VariableSymbol = struct {
    name: []const u8,
    type: ast.Type,
    is_global: bool,
    is_mutable: bool,
    loc: ast.SourceLocation,
};

/// Function symbol information
pub const FunctionSymbol = struct {
    name: []const u8,
    return_type: ast.Type,
    params: []const ast.Param,
    loc: ast.SourceLocation,
};

/// Type definition symbol information
pub const TypeSymbol = struct {
    name: []const u8,
    underlying_type: ast.Type,
    loc: ast.SourceLocation,
};
