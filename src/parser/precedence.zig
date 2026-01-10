//! Operator mapping utilities for the HolyC parser
//!
//! This module provides pure functions for converting tokens to operators.
//! No parser state is required, making these utilities easy to test and reuse.

const lexer = @import("../lexer/lexer.zig");
const ast = @import("ast.zig");

const TokenType = lexer.TokenType;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;

/// Convert a token type to a binary operator
/// Returns null if the token is not a binary operator
pub fn tokenToBinaryOp(token_type: TokenType) ?BinaryOp {
    return switch (token_type) {
        .op_plus => .add,
        .op_minus => .subtract,
        .op_star => .multiply,
        .op_slash => .divide,
        .op_percent => .modulo,
        .op_ampersand => .bitwise_and,
        .op_pipe => .bitwise_or,
        .op_caret => .bitwise_xor,
        .op_less_less => .shift_left,
        .op_greater_greater => .shift_right,
        .op_ampersand_ampersand => .logical_and,
        .op_pipe_pipe => .logical_or,
        .op_caret_caret => .logical_xor,
        .op_equal_equal => .equal,
        .op_not_equal => .not_equal,
        .op_less => .less,
        .op_less_equal => .less_equal,
        .op_greater => .greater,
        .op_greater_equal => .greater_equal,
        .op_equal => .assign,
        .op_plus_equal => .add_assign,
        .op_minus_equal => .sub_assign,
        .op_star_equal => .mul_assign,
        .op_slash_equal => .div_assign,
        .op_percent_equal => .mod_assign,
        .op_ampersand_equal => .and_assign,
        .op_pipe_equal => .or_assign,
        .op_caret_equal => .xor_assign,
        .op_less_less_equal => .shl_assign,
        .op_greater_greater_equal => .shr_assign,
        .op_backtick => .power,
        else => null,
    };
}

/// Convert a token type to a unary operator
/// Returns null if the token is not a unary operator
pub fn tokenToUnaryOp(token_type: TokenType) ?UnaryOp {
    return switch (token_type) {
        .op_minus => .negate,
        .op_plus => .plus,
        .op_exclamation => .logical_not,
        .op_tilde => .bitwise_not,
        .op_star => .dereference,
        .op_ampersand => .address_of,
        .op_plus_plus => .pre_increment,
        .op_minus_minus => .pre_decrement,
        else => null,
    };
}

/// Check if a token can start a type declaration
/// This is used to disambiguate between statements and declarations
pub fn isTypeStartToken(token_type: TokenType) bool {
    return switch (token_type) {
        .keyword_i0,
        .keyword_i8,
        .keyword_i16,
        .keyword_i32,
        .keyword_i64,
        .keyword_u0,
        .keyword_u8,
        .keyword_u16,
        .keyword_u32,
        .keyword_u64,
        .keyword_f64,
        => true,
        else => false,
    };
}
