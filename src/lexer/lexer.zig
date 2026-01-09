const std = @import("std");

// ============================================================================
// Module Imports and Re-exports
// ============================================================================

// Re-export token types from token module
pub const Token = @import("token.zig").Token;
pub const TokenType = @import("token.zig").TokenType;

// Import keywords module
const keywords_mod = @import("keywords.zig");

// Import helper functions
const helpers = @import("helpers.zig");

// ============================================================================
// Lexer Structure and Public API
// ============================================================================

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

        // Save position for token start
        const token_line = self.line;
        const token_column = self.column;

        if (self.position >= self.source.len) {
            return Token{
                .type = .eof,
                .lexeme = "",
                .line = token_line,
                .column = token_column,
            };
        }

        const c = self.source[self.position];

        // Identifiers and keywords
        if (helpers.isIdentifierStart(c)) {
            return self.scanIdentifier(token_line, token_column);
        }

        // Number literals
        if (helpers.helpers.isDigit(c)) {
            return self.scanNumber(token_line, token_column);
        }

        // String literals
        if (c == '"') {
            return self.scanString(token_line, token_column);
        }

        // Character literals (including multi-character constants)
        if (c == '\'') {
            return self.scanChar(token_line, token_column);
        }

        // Operators and delimiters
        switch (c) {
            '+' => return self.scanOperatorVariants(token_line, token_column, .op_plus, '+', .op_plus_plus, .op_plus_equal),
            '-' => return self.scanMinusOperator(token_line, token_column),
            '*' => return self.scanOperatorVariants(token_line, token_column, .op_star, null, null, .op_star_equal),
            '/' => return self.scanSlashOperator(token_line, token_column),
            '%' => return self.scanOperatorVariants(token_line, token_column, .op_percent, null, null, .op_percent_equal),
            '&' => return self.scanOperatorVariants(token_line, token_column, .op_ampersand, '&', .op_ampersand_ampersand, .op_ampersand_equal),
            '|' => return self.scanOperatorVariants(token_line, token_column, .op_pipe, '|', .op_pipe_pipe, .op_pipe_equal),
            '^' => return self.scanOperatorVariants(token_line, token_column, .op_caret, '^', .op_caret_caret, .op_caret_equal),
            '~' => return self.makeSingleCharToken(.op_tilde, token_line, token_column),
            '!' => return self.scanOperatorVariants(token_line, token_column, .op_exclamation, null, null, .op_not_equal),
            '<' => return self.scanShiftOperator(token_line, token_column, .op_less, .op_less_equal, .op_less_less, .op_less_less_equal, '<'),
            '>' => return self.scanShiftOperator(token_line, token_column, .op_greater, .op_greater_equal, .op_greater_greater, .op_greater_greater_equal, '>'),
            '=' => return self.scanOperatorVariants(token_line, token_column, .op_equal, '=', .op_equal_equal, null),
            '.' => return self.scanDotOperator(token_line, token_column),
            '`' => return self.makeSingleCharToken(.op_backtick, token_line, token_column),
            '?' => return self.makeSingleCharToken(.op_question, token_line, token_column),
            // Delimiters
            '(' => return self.makeSingleCharToken(.lparen, token_line, token_column),
            ')' => return self.makeSingleCharToken(.rparen, token_line, token_column),
            '{' => return self.makeSingleCharToken(.lbrace, token_line, token_column),
            '}' => return self.makeSingleCharToken(.rbrace, token_line, token_column),
            '[' => return self.makeSingleCharToken(.lbracket, token_line, token_column),
            ']' => return self.makeSingleCharToken(.rbracket, token_line, token_column),
            ';' => return self.makeSingleCharToken(.semicolon, token_line, token_column),
            ',' => return self.makeSingleCharToken(.comma, token_line, token_column),
            ':' => return self.makeSingleCharToken(.colon, token_line, token_column),
            '#' => return self.scanPreprocessorDirective(token_line, token_column),
            else => {},
        }

        // Invalid character
        self.advance();
        return Token{
            .type = .invalid,
            .lexeme = self.source[self.position - 1 .. self.position],
            .line = token_line,
            .column = token_column,
        };
    }

    // ========================================================================
    // Identifier and Keyword Scanning
    // ========================================================================

    /// Scan an identifier or keyword
    fn scanIdentifier(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;

        // Consume identifier characters
        while (self.position < self.source.len and helpers.isIdentifierContinue(self.source[self.position])) {
            self.advance();
        }

        const lexeme = self.source[start..self.position];

        // Check if it's a keyword
        const token_type = getKeyword(lexeme) orelse .identifier;
        return self.makeToken(token_type, start, token_line, token_column);
    }

    // ========================================================================
    // Preprocessor Directive Scanning
    // ========================================================================

    /// Scan a preprocessor directive (#define, #include, etc.)
    fn scanPreprocessorDirective(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance(); // consume '#'

        // Skip whitespace after '#' (allowed in C/HolyC: "# define" is valid)
        while (self.peek()) |c| {
            if (c == ' ' or c == '\t') {
                self.advance();
            } else {
                break;
            }
        }

        // Check if there's a directive name following
        if (self.peek()) |c| {
            if (helpers.isIdentifierStart(c)) {
                const directive_start = self.position;

                // Consume directive name
                while (self.position < self.source.len and helpers.isIdentifierContinue(self.source[self.position])) {
                    self.advance();
                }

                const directive_name = self.source[directive_start..self.position];

                // Check if it's a recognized preprocessor keyword
                if (getKeyword(directive_name)) |keyword_type| {
                    // Return the full lexeme including '#' and the directive name
                    return self.makeToken(keyword_type, start, token_line, token_column);
                }

                // Not a recognized directive, return hash token with the full content
                return self.makeToken(.hash, start, token_line, token_column);
            }
        }

        // Just '#' alone - return hash token
        return self.makeToken(.hash, start, token_line, token_column);
    }

    /// Advance position and update column
    fn advance(self: *Lexer) void {
        if (self.position < self.source.len) {
            self.position += 1;
            self.column += 1;
        }
    }

    /// Peek at current character without consuming
    fn peek(self: *Lexer) ?u8 {
        if (self.position < self.source.len) {
            return self.source[self.position];
        }
        return null;
    }

    /// Peek ahead n characters
    fn peekAhead(self: *Lexer, n: usize) ?u8 {
        if (self.position + n < self.source.len) {
            return self.source[self.position + n];
        }
        return null;
    }

    // ========================================================================
    // Token Creation Helpers
    // ========================================================================

    /// Create a token from a starting position
    fn makeToken(self: *Lexer, token_type: TokenType, start: usize, token_line: usize, token_column: usize) Token {
        return Token{
            .type = token_type,
            .lexeme = self.source[start..self.position],
            .line = token_line,
            .column = token_column,
        };
    }

    /// Create a single-character token and advance
    fn makeSingleCharToken(self: *Lexer, token_type: TokenType, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance();
        return self.makeToken(token_type, start, token_line, token_column);
    }

    /// Create a two-character token and advance twice
    fn makeTwoCharToken(self: *Lexer, token_type: TokenType, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance();
        self.advance();
        return self.makeToken(token_type, start, token_line, token_column);
    }

    /// Create a three-character token and advance three times
    fn makeThreeCharToken(self: *Lexer, token_type: TokenType, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance();
        self.advance();
        self.advance();
        return self.makeToken(token_type, start, token_line, token_column);
    }

    // ========================================================================
    // Operator Scanning
    // ========================================================================

    /// Helper for scanning operators that can be single, double, or have compound assignment
    /// Returns the appropriate token based on what follows the initial operator character
    /// Examples: + (op_plus), ++ (op_plus_plus), += (op_plus_equal)
    fn scanOperatorVariants(
        self: *Lexer,
        token_line: usize,
        token_column: usize,
        single_op: TokenType,
        double_char: ?u8,
        double_op: ?TokenType,
        compound_op: ?TokenType,
    ) Token {
        const start = self.position;
        self.advance(); // consume first character

        if (self.peek()) |next| {
            // Check for compound assignment (e.g., +=)
            if (compound_op != null and next == '=') {
                self.advance();
                return self.makeToken(compound_op.?, start, token_line, token_column);
            }
            // Check for double character operator (e.g., ++)
            if (double_char != null and double_op != null and next == double_char.?) {
                self.advance();
                return self.makeToken(double_op.?, start, token_line, token_column);
            }
        }

        // Just the single character operator
        return self.makeToken(single_op, start, token_line, token_column);
    }

    /// Helper for scanning shift operators (< and >) with their variants
    /// Handles: <, <=, <<, <<=, >, >=, >>, >>=
    fn scanShiftOperator(
        self: *Lexer,
        token_line: usize,
        token_column: usize,
        single_op: TokenType,
        equal_op: TokenType,
        shift_op: TokenType,
        shift_equal_op: TokenType,
        shift_char: u8,
    ) Token {
        const start = self.position;
        self.advance(); // consume < or >

        if (self.peek()) |next| {
            if (next == '=') {
                // <= or >=
                self.advance();
                return self.makeToken(equal_op, start, token_line, token_column);
            }
            if (next == shift_char) {
                // << or >>
                self.advance();
                // Check for <<= or >>=
                if (self.peek()) |next2| {
                    if (next2 == '=') {
                        self.advance();
                        return self.makeToken(shift_equal_op, start, token_line, token_column);
                    }
                }
                return self.makeToken(shift_op, start, token_line, token_column);
            }
        }

        // Just < or >
        return self.makeToken(single_op, start, token_line, token_column);
    }

    /// Helper for scanning minus operator with its variants
    /// Handles: -, --, -=, ->
    fn scanMinusOperator(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance(); // consume -

        if (self.peek()) |next| {
            switch (next) {
                '-' => {
                    self.advance();
                    return self.makeToken(.op_minus_minus, start, token_line, token_column);
                },
                '=' => {
                    self.advance();
                    return self.makeToken(.op_minus_equal, start, token_line, token_column);
                },
                '>' => {
                    self.advance();
                    return self.makeToken(.op_arrow, start, token_line, token_column);
                },
                else => {},
            }
        }

        return self.makeToken(.op_minus, start, token_line, token_column);
    }

    /// Helper for scanning slash operator with comment handling
    /// Handles: /, /=, //, /* */
    fn scanSlashOperator(self: *Lexer, token_line: usize, token_column: usize) !Token {
        // Check for comments first
        if (self.position + 1 < self.source.len) {
            const next = self.source[self.position + 1];
            if (next == '/') {
                // Line comment - skip and get next token
                self.skipLineComment();
                return self.nextToken();
            } else if (next == '*') {
                // Block comment - skip and get next token
                self.skipBlockComment();
                return self.nextToken();
            }
        }

        // Not a comment, handle as operator
        const start = self.position;
        self.advance();

        if (self.peek()) |next| {
            if (next == '=') {
                self.advance();
                return self.makeToken(.op_slash_equal, start, token_line, token_column);
            }
        }

        return self.makeToken(.op_slash, start, token_line, token_column);
    }

    /// Helper for scanning dot operator with ellipsis handling
    /// Handles: ., ...
    fn scanDotOperator(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance(); // consume first .

        // Check for ... (ellipsis)
        if (self.peek()) |next| {
            if (next == '.') {
                if (self.peekAhead(1)) |next2| {
                    if (next2 == '.') {
                        self.advance();
                        self.advance();
                        return self.makeToken(.op_ellipsis, start, token_line, token_column);
                    }
                }
            }
        }

        return self.makeToken(.op_dot, start, token_line, token_column);
    }

    // ========================================================================
    // Whitespace and Comment Handling
    // ========================================================================

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

    /// Skip a line comment (// until end of line)
    fn skipLineComment(self: *Lexer) void {
        // Skip the //
        self.advance();
        self.advance();

        // Skip until newline or EOF
        while (self.position < self.source.len and self.source[self.position] != '\n') {
            self.advance();
        }
    }

    /// Skip a block comment (/* ... */)
    fn skipBlockComment(self: *Lexer) void {
        // Skip the /*
        self.advance();
        self.advance();

        // Skip until */ or EOF
        while (self.position < self.source.len) {
            if (self.source[self.position] == '*' and self.position + 1 < self.source.len and self.source[self.position + 1] == '/') {
                // Found end of comment
                self.advance(); // *
                self.advance(); // /
                return;
            }

            // Track line numbers in block comments
            if (self.source[self.position] == '\n') {
                self.position += 1;
                self.line += 1;
                self.column = 1;
            } else {
                self.advance();
            }
        }
        // If we reach here, we hit EOF before closing the comment
        // For now, we just return (could be an error in a more robust implementation)
    }

    // ========================================================================
    // Character Classification Helpers
    // ========================================================================

    /// Check if a string is a keyword and return its token type
    fn getKeyword(str: []const u8) ?TokenType {
        return keywords_mod.getKeyword(str);
    }

    // ========================================================================
    // Number Literal Scanning
    // ========================================================================

    /// Scan a number literal (integer or float)
    fn scanNumber(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;

        // Check for hex (0x) or binary (0b) prefix
        if (self.source[self.position] == '0' and self.position + 1 < self.source.len) {
            const next = self.source[self.position + 1];
            if (next == 'x' or next == 'X') {
                // Hexadecimal
                self.advance(); // '0'
                self.advance(); // 'x'
                while (self.position < self.source.len) {
                    const c = self.source[self.position];
                    if (helpers.isHexDigit(c) or c == '_') {
                        self.advance();
                    } else {
                        break;
                    }
                }
                return self.makeToken(.integer_literal, start, token_line, token_column);
            } else if (next == 'b' or next == 'B') {
                // Binary
                self.advance(); // '0'
                self.advance(); // 'b'
                while (self.position < self.source.len) {
                    const c = self.source[self.position];
                    if (helpers.isBinaryDigit(c) or c == '_') {
                        self.advance();
                    } else {
                        break;
                    }
                }
                return self.makeToken(.integer_literal, start, token_line, token_column);
            }
        }

        // Decimal integer or float
        var has_dot = false;
        while (self.position < self.source.len) {
            const c = self.source[self.position];
            if (helpers.isDigit(c) or c == '_') {
                self.advance();
            } else if (c == '.' and !has_dot) {
                // Check if this is a decimal point (not an ellipsis or field access)
                if (self.position + 1 < self.source.len) {
                    const next_char = self.source[self.position + 1];
                    if (helpers.isDigit(next_char)) {
                        // This is a float
                        has_dot = true;
                        self.advance();
                    } else {
                        // This is not part of the number
                        break;
                    }
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        // Check for scientific notation (e.g., 1.5e10, 3e-5)
        if (self.position < self.source.len) {
            const c = self.source[self.position];
            if (c == 'e' or c == 'E') {
                self.advance();
                // Check for optional + or - sign
                if (self.position < self.source.len) {
                    const sign = self.source[self.position];
                    if (sign == '+' or sign == '-') {
                        self.advance();
                    }
                }
                // Consume exponent digits
                while (self.position < self.source.len) {
                    const exp_c = self.source[self.position];
                    if (helpers.isDigit(exp_c) or exp_c == '_') {
                        self.advance();
                    } else {
                        break;
                    }
                }
                has_dot = true; // Treat scientific notation as float
            }
        }

        const token_type = if (has_dot) TokenType.float_literal else TokenType.integer_literal;
        return self.makeToken(token_type, start, token_line, token_column);
    }

    // ========================================================================
    // String and Character Literal Scanning
    // ========================================================================

    /// Scan a string literal
    fn scanString(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance(); // Opening "

        // Scan until closing " or EOF
        while (self.position < self.source.len and self.source[self.position] != '"') {
            // Handle escape sequences
            if (self.source[self.position] == '\\') {
                self.advance(); // Skip backslash
                if (self.position < self.source.len) {
                    self.advance(); // Skip escaped character
                }
            } else if (self.source[self.position] == '\n') {
                // Newline in string (could be error, but for now we allow it)
                self.position += 1;
                self.line += 1;
                self.column = 1;
            } else {
                self.advance();
            }
        }

        // Consume closing "
        if (self.position < self.source.len and self.source[self.position] == '"') {
            self.advance();
        }

        return self.makeToken(.string_literal, start, token_line, token_column);
    }

    /// Scan a character literal (including multi-character constants in HolyC)
    fn scanChar(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;
        self.advance(); // Opening '

        // Scan until closing ' or EOF
        while (self.position < self.source.len and self.source[self.position] != '\'') {
            // Handle escape sequences
            if (self.source[self.position] == '\\') {
                self.advance(); // Skip backslash
                if (self.position < self.source.len) {
                    self.advance(); // Skip escaped character
                }
            } else {
                self.advance();
            }
        }

        // Consume closing '
        if (self.position < self.source.len and self.source[self.position] == '\'') {
            self.advance();
        }

        return self.makeToken(.char_literal, start, token_line, token_column);
    }
};

// ============================================================================
// Tests
// ============================================================================

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

// ============================================================================
// Tests (in separate file)
// ============================================================================
test { _ = @import("tests.zig"); }
