//! Expression Evaluator for Assembly Context
//!
//! This module evaluates HolyC constant expressions that appear in assembly code.
//! Examples:
//!   - MOV RAX, U64 8[RBP]             // Simple numeric constant
//!   - MOV RCX, I64 sizeof(MyStruct)[RBP]  // sizeof operator
//!   - MOV RDX, U64 &myvar[RBP]        // Address-of variable
//!   - MOV RSI, I32 MyStruct.field>>3  // Struct offset with arithmetic
//!
//! Since the assembler runs independently from the compiler, we have limited
//! information available. This evaluator handles:
//!   1. Numeric constants (decimal, hex)
//!   2. Basic arithmetic operators (+, -, *, /, %, <<, >>)
//!   3. sizeof() operator (requires type information)
//!   4. Address-of operator & (requires symbol table)
//!   5. Struct member access (requires type layout information)
//!
//! For full expression evaluation, the assembler needs access to:
//!   - Symbol table (for variable addresses/offsets)
//!   - Type information (for sizeof and struct layouts)
//!   - Constant definitions (for named constants)

const std = @import("std");
const assembler = @import("assembler.zig");

/// Expression evaluation context
/// Contains symbol table and type information needed for evaluation
pub const EvalContext = struct {
    allocator: std.mem.Allocator,
    
    // TODO: Add symbol table reference
    // symbols: *SymbolTable,
    
    // TODO: Add type registry reference  
    // types: *TypeRegistry,
    
    // For now, we only support numeric constants
    // Full integration requires compiler symbol table access
    
    pub fn init(allocator: std.mem.Allocator) EvalContext {
        return .{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EvalContext) void {
        _ = self;
        // Nothing to clean up yet
    }
};

/// Evaluate a constant expression to an integer value
/// Returns null if the expression cannot be evaluated at compile time
pub fn evalConstExpr(ctx: *EvalContext, expr: []const u8) error{OutOfMemory}!?i64 {
    const trimmed = std.mem.trim(u8, expr, &std.ascii.whitespace);
    
    // Try to parse as hex literal
    if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
        return std.fmt.parseInt(i64, trimmed[2..], 16) catch null;
    }
    
    // Try to parse as decimal literal
    if (std.fmt.parseInt(i64, trimmed, 10)) |value| {
        return value;
    } else |_| {
        // Not a simple integer
    }
    
    // Check for sizeof() operator
    if (std.mem.startsWith(u8, trimmed, "sizeof(") and std.mem.endsWith(u8, trimmed, ")")) {
        return try evalSizeof(ctx, trimmed[7..trimmed.len-1]);
    }
    
    // Check for address-of operator &
    if (std.mem.startsWith(u8, trimmed, "&")) {
        return try evalAddressOf(ctx, trimmed[1..]);
    }
    
    // Check for binary operators
    if (try evalBinaryExpr(ctx, trimmed)) |value| {
        return value;
    }
    
    // TODO: Check for struct member access (Type.member)
    
    // TODO: Check for symbolic constants
    
    return null;
}

/// Evaluate sizeof(Type) expression
fn evalSizeof(ctx: *EvalContext, type_name: []const u8) error{OutOfMemory}!?i64 {
    _ = ctx;
    
    const trimmed = std.mem.trim(u8, type_name, &std.ascii.whitespace);
    
    // For now, only handle basic types
    // TODO: Integrate with compiler's type system
    if (std.mem.eql(u8, trimmed, "U8") or std.mem.eql(u8, trimmed, "I8")) return 1;
    if (std.mem.eql(u8, trimmed, "U16") or std.mem.eql(u8, trimmed, "I16")) return 2;
    if (std.mem.eql(u8, trimmed, "U32") or std.mem.eql(u8, trimmed, "I32") or std.mem.eql(u8, trimmed, "F32")) return 4;
    if (std.mem.eql(u8, trimmed, "U64") or std.mem.eql(u8, trimmed, "I64") or std.mem.eql(u8, trimmed, "F64")) return 8;
    if (std.mem.eql(u8, trimmed, "U0") or std.mem.eql(u8, trimmed, "I0")) return 0;
    
    // Unknown type - requires type registry
    return null;
}

/// Evaluate &variable expression
fn evalAddressOf(ctx: *EvalContext, var_name: []const u8) error{OutOfMemory}!?i64 {
    _ = ctx;
    _ = var_name;
    
    // TODO: Look up variable in symbol table and return its address/offset
    // This requires integration with compiler's symbol table
    return null;
}

/// Try to evaluate a binary expression (e.g., "8+4", "16>>2")
fn evalBinaryExpr(ctx: *EvalContext, expr: []const u8) error{OutOfMemory}!?i64 {
    // Try each binary operator
    const operators = [_][]const u8{ "<<", ">>", "+", "-", "*", "/", "%" };
    
    for (operators) |op| {
        if (std.mem.indexOf(u8, expr, op)) |op_pos| {
            const left_str = std.mem.trim(u8, expr[0..op_pos], &std.ascii.whitespace);
            const right_str = std.mem.trim(u8, expr[op_pos+op.len..], &std.ascii.whitespace);
            
            const left = (try evalConstExpr(ctx, left_str)) orelse continue;
            const right = (try evalConstExpr(ctx, right_str)) orelse continue;
            
            return switch (op[0]) {
                '+' => left + right,
                '-' => left - right,
                '*' => left * right,
                '/' => if (right != 0) @divTrunc(left, right) else null,
                '%' => if (right != 0) @rem(left, right) else null,
                '<' => left << @intCast(right), // <<
                '>' => left >> @intCast(right), // >>
                else => null,
            };
        }
    }
    
    return null;
}

// Tests
test "evalConstExpr - simple numbers" {
    var ctx = EvalContext.init(std.testing.allocator);
    defer ctx.deinit();
    
    try std.testing.expectEqual(@as(i64, 42), (try evalConstExpr(&ctx, "42")).?);
    try std.testing.expectEqual(@as(i64, 255), (try evalConstExpr(&ctx, "0xFF")).?);
    try std.testing.expectEqual(@as(i64, -10), (try evalConstExpr(&ctx, "-10")).?);
}

test "evalConstExpr - sizeof basic types" {
    var ctx = EvalContext.init(std.testing.allocator);
    defer ctx.deinit();
    
    try std.testing.expectEqual(@as(i64, 1), (try evalConstExpr(&ctx, "sizeof(U8)")).?);
    try std.testing.expectEqual(@as(i64, 2), (try evalConstExpr(&ctx, "sizeof(U16)")).?);
    try std.testing.expectEqual(@as(i64, 4), (try evalConstExpr(&ctx, "sizeof(U32)")).?);
    try std.testing.expectEqual(@as(i64, 8), (try evalConstExpr(&ctx, "sizeof(U64)")).?);
}

test "evalConstExpr - binary operations" {
    var ctx = EvalContext.init(std.testing.allocator);
    defer ctx.deinit();
    
    try std.testing.expectEqual(@as(i64, 12), (try evalConstExpr(&ctx, "8+4")).?);
    try std.testing.expectEqual(@as(i64, 4), (try evalConstExpr(&ctx, "8-4")).?);
    try std.testing.expectEqual(@as(i64, 32), (try evalConstExpr(&ctx, "8*4")).?);
    try std.testing.expectEqual(@as(i64, 2), (try evalConstExpr(&ctx, "8/4")).?);
    try std.testing.expectEqual(@as(i64, 4), (try evalConstExpr(&ctx, "16>>2")).?);
    try std.testing.expectEqual(@as(i64, 64), (try evalConstExpr(&ctx, "16<<2")).?);
}
