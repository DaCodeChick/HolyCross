//! Type checker for semantic analysis
//!
//! Handles:
//! - Expression type inference
//! - Type compatibility checking
//! - Implicit type conversions (HolyC is weakly typed)
//! - Operator type validation
//!
//! HolyC Type System:
//! - Weakly typed with implicit conversions
//! - All integer types can convert to each other
//! - Integers can convert to floats
//! - Pointers and integers are interchangeable (for pointer arithmetic)
//! - No implicit conversions between incompatible pointer types

const std = @import("std");
const ast = @import("../parser/ast.zig");
const symbol_table = @import("symbol_table.zig");
const symbol_module = @import("symbol.zig");

const Allocator = std.mem.Allocator;
const SymbolTable = symbol_table.SymbolTable;

/// Error set for type checking operations
pub const TypeCheckError = error{
    TypeError,
    OutOfMemory,
};

/// Type checker for expressions and statements
pub const TypeChecker = struct {
    symbol_table: *SymbolTable,
    allocator: Allocator,
    type_arena: std.heap.ArenaAllocator, // Arena for Type* allocations
    errors: std.ArrayList(TypeError),

    pub fn init(allocator: Allocator, sym_table: *SymbolTable) TypeChecker {
        return .{
            .symbol_table = sym_table,
            .allocator = allocator,
            .type_arena = std.heap.ArenaAllocator.init(allocator),
            .errors = .{},
        };
    }

    pub fn deinit(self: *TypeChecker) void {
        for (self.errors.items) |err| {
            self.allocator.free(err.message);
        }
        self.errors.deinit(self.allocator);
        self.type_arena.deinit(); // Frees all Type* allocations
    }

    /// Add a type error
    fn addError(self: *TypeChecker, kind: TypeErrorKind, message: []const u8, loc: ast.SourceLocation) TypeCheckError!void {
        const owned_message = try self.allocator.dupe(u8, message);
        try self.errors.append(self.allocator, .{
            .kind = kind,
            .message = owned_message,
            .loc = loc,
        });
    }

    // ============================================================================
    // Expression Type Inference
    // ============================================================================

    /// Infer the type of an expression
    pub fn inferExprType(self: *TypeChecker, expr: ast.Expr) TypeCheckError!ast.Type {
        return switch (expr) {
            .integer => .i64, // Default integer type
            .float => .f64,
            .string => blk: {
                // String literals are U8* (pointer to U8)
                const u8_type = try self.type_arena.allocator().create(ast.Type);
                u8_type.* = .u8;
                break :blk ast.Type{ .pointer = u8_type };
            },
            .char => .i32, // HolyC uses I32 for char
            .identifier => |id| try self.inferIdentifierType(id.name, id.loc),
            .binary => |bin| try self.inferBinaryOpType(bin.left.*, bin.op, bin.right.*),
            .unary => |un| try self.inferUnaryOpType(un.op, un.operand.*),
            .call => |call| try self.inferCallType(call.callee.*, call.args),
            .subscript => |sub| try self.inferSubscriptType(sub.array.*, sub.index.*),
            .member => |mem| try self.inferMemberType(mem.object.*, mem.member),
            .arrow => |arr| try self.inferMemberType(arr.object.*, arr.member),
            .cast => |c| c.type,
            .sizeof_expr, .sizeof_type => .u64, // sizeof returns U64
            .offset => .u64, // offset returns U64
        };
    }

    /// Infer type of an identifier
    fn inferIdentifierType(self: *TypeChecker, name: []const u8, loc: ast.SourceLocation) TypeCheckError!ast.Type {
        if (self.symbol_table.lookupSymbol(name)) |symbol| {
            return switch (symbol) {
                .variable => |v| v.type,
                .function => |f| blk: {
                    // Allocate return type on heap for function pointer type
                    const return_type_ptr = try self.type_arena.allocator().create(ast.Type);
                    return_type_ptr.* = f.return_type;
                    break :blk ast.Type{
                        .function = .{
                            .return_type = return_type_ptr,
                            .params = &[_]ast.Type{}, // Simplified for now
                        },
                    };
                },
                .type_def => {
                    const msg = try std.fmt.allocPrint(self.allocator, "'{s}' is a type, not a variable", .{name});
                    defer self.allocator.free(msg);
                    try self.addError(.type_expected_value, msg, loc);
                    return error.TypeError;
                },
            };
        }

        const msg = try std.fmt.allocPrint(self.allocator, "Undeclared identifier '{s}'", .{name});
        defer self.allocator.free(msg);
        try self.addError(.undeclared_identifier, msg, loc);
        return error.TypeError;
    }

    /// Infer type of binary operation
    fn inferBinaryOpType(self: *TypeChecker, left: ast.Expr, op: ast.BinaryOp, right: ast.Expr) TypeCheckError!ast.Type {
        const left_type = try self.inferExprType(left);
        const right_type = try self.inferExprType(right);

        return switch (op) {
            // Arithmetic operators: return larger of the two types
            .add, .subtract, .multiply, .divide, .modulo => try self.arithmeticResultType(left_type, right_type),

            // Bitwise operators: return integer type
            .bitwise_and, .bitwise_or, .bitwise_xor, .shift_left, .shift_right => blk: {
                if (!self.isIntegerType(left_type) or !self.isIntegerType(right_type)) {
                    try self.addError(.invalid_operation, "Bitwise operations require integer types", left.getLocation());
                    return error.TypeError;
                }
                break :blk self.promoteIntegerTypes(left_type, right_type);
            },

            // Comparison operators: return I64 (boolean represented as int in HolyC)
            .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => .i64,

            // Logical operators: return I64
            .logical_and, .logical_or, .logical_xor => .i64,

            // Assignment: return left type
            .assign,
            .add_assign,
            .sub_assign,
            .mul_assign,
            .div_assign,
            .mod_assign,
            .and_assign,
            .or_assign,
            .xor_assign,
            .shl_assign,
            .shr_assign,
            => blk: {
                // Check assignment compatibility
                if (!try self.areTypesCompatible(right_type, left_type)) {
                    try self.addError(.type_mismatch, "Type mismatch in assignment", left.getLocation());
                    return error.TypeError;
                }
                break :blk left_type;
            },

            .power => blk: {
                // Power operator: return left type
                if (!self.isNumericType(left_type) or !self.isNumericType(right_type)) {
                    try self.addError(.invalid_operation, "Power operation requires numeric types", left.getLocation());
                    return error.TypeError;
                }
                break :blk left_type;
            },
        };
    }

    /// Infer type of unary operation
    fn inferUnaryOpType(self: *TypeChecker, op: ast.UnaryOp, operand: ast.Expr) TypeCheckError!ast.Type {
        const operand_type = try self.inferExprType(operand);

        return switch (op) {
            .negate, .plus => blk: {
                if (!self.isNumericType(operand_type)) {
                    try self.addError(.invalid_operation, "Unary +/- requires numeric type", operand.getLocation());
                    return error.TypeError;
                }
                break :blk operand_type;
            },

            .bitwise_not => blk: {
                if (!self.isIntegerType(operand_type)) {
                    try self.addError(.invalid_operation, "Bitwise NOT requires integer type", operand.getLocation());
                    return error.TypeError;
                }
                break :blk operand_type;
            },

            .logical_not => .i64, // Returns boolean (I64 in HolyC)

            .pre_increment, .pre_decrement, .post_increment, .post_decrement => blk: {
                if (!self.isNumericType(operand_type) and !self.isPointerType(operand_type)) {
                    try self.addError(.invalid_operation, "Increment/decrement requires numeric or pointer type", operand.getLocation());
                    return error.TypeError;
                }
                break :blk operand_type;
            },

            .address_of => blk: {
                // Create a pointer type pointing to the operand's type
                const ptr_type = try self.type_arena.allocator().create(ast.Type);
                ptr_type.* = operand_type;
                break :blk ast.Type{ .pointer = ptr_type };
            },

            .dereference => blk: {
                if (!self.isPointerType(operand_type)) {
                    try self.addError(.invalid_operation, "Dereference requires pointer type", operand.getLocation());
                    return error.TypeError;
                }
                // Return pointed-to type
                break :blk switch (operand_type) {
                    .pointer => |ptr| ptr.*,
                    else => unreachable,
                };
            },
        };
    }

    /// Infer type of function call
    fn inferCallType(self: *TypeChecker, callee: ast.Expr, args: []const ast.Expr) TypeCheckError!ast.Type {
        _ = args; // TODO: validate argument types
        const callee_type = try self.inferExprType(callee);

        return switch (callee_type) {
            .function => |func| func.return_type.*,
            else => {
                try self.addError(.not_callable, "Expression is not callable", callee.getLocation());
                return error.TypeError;
            },
        };
    }

    /// Infer type of array subscript
    fn inferSubscriptType(self: *TypeChecker, array: ast.Expr, index: ast.Expr) TypeCheckError!ast.Type {
        _ = index; // TODO: validate index is integer
        const array_type = try self.inferExprType(array);

        return switch (array_type) {
            .array => |arr| arr.element_type.*,
            .pointer => |ptr| ptr.*,
            else => {
                try self.addError(.invalid_subscript, "Subscript requires array or pointer", array.getLocation());
                return error.TypeError;
            },
        };
    }

    /// Infer type of member access
    fn inferMemberType(self: *TypeChecker, object: ast.Expr, member: []const u8) TypeCheckError!ast.Type {
        _ = object;
        _ = member;
        // TODO: Implement member type lookup for classes/unions
        try self.addError(.not_implemented, "Member access type checking not yet implemented", ast.SourceLocation{ .line = 0, .column = 0 });
        return error.TypeError;
    }

    // ============================================================================
    // Type Compatibility and Conversion
    // ============================================================================

    /// Check if two types are compatible for assignment (HolyC weak typing rules)
    pub fn areTypesCompatible(self: *TypeChecker, from: ast.Type, to: ast.Type) TypeCheckError!bool {
        // Exact match
        if (std.meta.eql(from, to)) return true;

        // Integer to integer conversion (always allowed in HolyC)
        if (self.isIntegerType(from) and self.isIntegerType(to)) return true;

        // Integer to float conversion
        if (self.isIntegerType(from) and self.isFloatType(to)) return true;

        // Pointer to integer conversion (HolyC allows this)
        if (self.isPointerType(from) and self.isIntegerType(to)) return true;

        // Integer to pointer conversion (HolyC allows this)
        if (self.isIntegerType(from) and self.isPointerType(to)) return true;

        // Pointer to pointer conversion (void pointers - U0*)
        if (self.isPointerType(from) and self.isPointerType(to)) {
            // TODO: Check for U0* (void pointer) compatibility
            return true;
        }

        return false;
    }

    /// Check if a type can be implicitly cast to another
    pub fn canImplicitCast(self: *TypeChecker, from: ast.Type, to: ast.Type) bool {
        return self.areTypesCompatible(from, to) catch false;
    }

    // ============================================================================
    // Type Classification Helpers
    // ============================================================================

    /// Check if type is an integer type
    pub fn isIntegerType(self: *TypeChecker, typ: ast.Type) bool {
        _ = self;
        return switch (typ) {
            .i0, .i8, .i16, .i32, .i64, .u0, .u8, .u16, .u32, .u64 => true,
            else => false,
        };
    }

    /// Check if type is a floating point type
    pub fn isFloatType(self: *TypeChecker, typ: ast.Type) bool {
        _ = self;
        return switch (typ) {
            .f64 => true,
            else => false,
        };
    }

    /// Check if type is numeric (integer or float)
    pub fn isNumericType(self: *TypeChecker, typ: ast.Type) bool {
        return self.isIntegerType(typ) or self.isFloatType(typ);
    }

    /// Check if type is a pointer type
    pub fn isPointerType(self: *TypeChecker, typ: ast.Type) bool {
        _ = self;
        return switch (typ) {
            .pointer => true,
            else => false,
        };
    }

    /// Get size of an integer type in bits
    pub fn getIntegerSize(self: *TypeChecker, typ: ast.Type) u32 {
        _ = self;
        return switch (typ) {
            .i0, .u0 => 0,
            .i8, .u8 => 8,
            .i16, .u16 => 16,
            .i32, .u32 => 32,
            .i64, .u64 => 64,
            else => 0,
        };
    }

    // ============================================================================
    // Type Arithmetic and Promotion
    // ============================================================================

    /// Get result type of arithmetic operation
    pub fn arithmeticResultType(self: *TypeChecker, left: ast.Type, right: ast.Type) TypeCheckError!ast.Type {
        // Float takes precedence
        if (self.isFloatType(left) or self.isFloatType(right)) return .f64;

        // Both are integers - promote to larger
        if (self.isIntegerType(left) and self.isIntegerType(right)) {
            return self.promoteIntegerTypes(left, right);
        }

        // Pointer arithmetic: ptr + int = ptr
        if (self.isPointerType(left) and self.isIntegerType(right)) return left;
        if (self.isIntegerType(left) and self.isPointerType(right)) return right;

        try self.addError(.invalid_operation, "Invalid types for arithmetic", ast.SourceLocation{ .line = 0, .column = 0 });
        return error.TypeError;
    }

    /// Promote two integer types to the larger one
    pub fn promoteIntegerTypes(self: *TypeChecker, left: ast.Type, right: ast.Type) ast.Type {
        const left_size = self.getIntegerSize(left);
        const right_size = self.getIntegerSize(right);

        if (left_size >= right_size) return left;
        return right;
    }
};

// ============================================================================
// Type Error Definitions
// ============================================================================

pub const TypeError = struct {
    kind: TypeErrorKind,
    message: []const u8,
    loc: ast.SourceLocation,
};

pub const TypeErrorKind = enum {
    undeclared_identifier,
    redeclared_identifier,
    type_mismatch,
    invalid_operation,
    invalid_cast,
    invalid_subscript,
    not_callable,
    type_expected_value,
    not_implemented,
    argument_count_mismatch,
    argument_type_mismatch,
};

// Import tests
test {
    _ = @import("tests/type_checker_tests.zig");
}
