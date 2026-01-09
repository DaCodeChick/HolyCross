const std = @import("std");

/// Token types for HolyC lexer
pub const TokenType = enum {
    // Literals
    integer_literal,
    float_literal,
    string_literal,
    char_literal,

    // Keywords
    keyword_u0, // void (zero-sized)
    keyword_u8,
    keyword_u16,
    keyword_u32,
    keyword_u64,
    keyword_i8,
    keyword_i16,
    keyword_i32,
    keyword_i64,
    keyword_f64,
    keyword_class,
    keyword_union,
    keyword_if,
    keyword_else,
    keyword_while,
    keyword_for,
    keyword_switch,
    keyword_case,
    keyword_default,
    keyword_break,
    keyword_continue,
    keyword_return,
    keyword_try,
    keyword_catch,
    keyword_throw,
    keyword_asm,
    keyword_sizeof,
    keyword_offset,

    // Identifiers
    identifier,

    // Operators
    op_plus, // +
    op_minus, // -
    op_star, // *
    op_slash, // /
    op_percent, // %
    op_ampersand, // &
    op_pipe, // |
    op_caret, // ^
    op_tilde, // ~
    op_exclamation, // !
    op_less, // <
    op_greater, // >
    op_equal, // =
    op_less_equal, // <=
    op_greater_equal, // >=
    op_equal_equal, // ==
    op_not_equal, // !=
    op_ampersand_ampersand, // &&
    op_pipe_pipe, // ||
    op_less_less, // <<
    op_greater_greater, // >>
    op_plus_plus, // ++
    op_minus_minus, // --
    op_arrow, // ->
    op_dot, // .
    op_backtick, // ` (power operator in HolyC)

    // Delimiters
    lparen, // (
    rparen, // )
    lbrace, // {
    rbrace, // }
    lbracket, // [
    rbracket, // ]
    semicolon, // ;
    comma, // ,
    colon, // :

    // Special
    eof,
    invalid,
};

/// A token with its type, location, and lexeme
pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

/// Lexer for HolyC source code
pub const Lexer = struct {
    source: []const u8,
    position: usize,
    line: usize,
    column: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .position = 0,
            .line = 1,
            .column = 1,
            .allocator = allocator,
        };
    }

    pub fn nextToken(self: *Lexer) !Token {
        // Skip whitespace
        self.skipWhitespace();

        if (self.position >= self.source.len) {
            return Token{
                .type = .eof,
                .lexeme = "",
                .line = self.line,
                .column = self.column,
            };
        }

        // TODO: Implement tokenization logic
        // For now, just return EOF
        return Token{
            .type = .eof,
            .lexeme = "",
            .line = self.line,
            .column = self.column,
        };
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.position < self.source.len) {
            const c = self.source[self.position];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.position += 1;
                self.column += 1;
            } else if (c == '\n') {
                self.position += 1;
                self.line += 1;
                self.column = 1;
            } else {
                break;
            }
        }
    }
};

test "lexer initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "I64 x = 42;";
    const lexer = Lexer.init(allocator, source);

    try testing.expect(lexer.position == 0);
    try testing.expect(lexer.line == 1);
    try testing.expect(lexer.column == 1);
}

test "lexer EOF" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .eof);
}
