const std = @import("std");

/// Token types for HolyC lexer
/// Complete list based on TempleOS Compiler/OpCodes.DD and CompilerA.HH
pub const TokenType = enum {
    // Literals
    integer_literal,
    float_literal,
    string_literal,
    char_literal,

    // Type Keywords (I0-I64, U0-U64, F64)
    keyword_i0, // void signed (zero-sized)
    keyword_i8,
    keyword_i16,
    keyword_i32,
    keyword_i64,
    keyword_u0, // void unsigned (zero-sized)
    keyword_u8,
    keyword_u16,
    keyword_u32,
    keyword_u64,
    keyword_f64,

    // Control Flow Keywords
    keyword_if,
    keyword_else,
    keyword_while,
    keyword_for,
    keyword_do,
    keyword_switch,
    keyword_case,
    keyword_default,
    keyword_break,
    keyword_return,
    keyword_goto,

    // Class/Type Keywords
    keyword_class,
    keyword_union,
    keyword_sizeof,
    keyword_offset,
    keyword_lastclass,

    // Exception Handling
    keyword_try,
    keyword_catch,

    // Inline Assembly
    keyword_asm,

    // Linkage/Visibility Keywords
    keyword_extern,
    keyword_import,
    keyword_public,
    keyword_static,
    keyword__extern, // underscore variant
    keyword__import, // underscore variant
    keyword__intern,

    // Function Attributes
    keyword_interrupt,
    keyword_haserrcode,
    keyword_argpop,
    keyword_noargpop,
    keyword_lock,

    // Register Hints
    keyword_reg,
    keyword_noreg,

    // Preprocessor Keywords (recognized as keywords, but handled specially)
    keyword_define,
    keyword_defined,
    keyword_include,
    keyword_ifdef,
    keyword_ifndef,
    keyword_ifaot, // if ahead-of-time compiling
    keyword_ifjit, // if just-in-time compiling
    keyword_endif,
    keyword_assert,
    keyword_exe, // compile-time execution

    // Block Markers
    keyword_start,
    keyword_end,

    // Special Keywords
    keyword_no_warn,
    keyword_help_file,
    keyword_help_index,

    // Assembly Directives (used in asm blocks)
    keyword_align,
    keyword_org,
    keyword_binfile,
    keyword_du8,
    keyword_du16,
    keyword_du32,
    keyword_du64,
    keyword_dup,
    keyword_use16,
    keyword_use32,
    keyword_use64,
    keyword_list,
    keyword_nolist,

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
    op_caret_caret, // ^^ (logical XOR in HolyC)
    op_less_less, // <<
    op_greater_greater, // >>
    op_plus_plus, // ++
    op_minus_minus, // --
    op_plus_equal, // +=
    op_minus_equal, // -=
    op_star_equal, // *=
    op_slash_equal, // /=
    op_percent_equal, // %=
    op_ampersand_equal, // &=
    op_pipe_equal, // |=
    op_caret_equal, // ^=
    op_less_less_equal, // <<=
    op_greater_greater_equal, // >>=
    op_arrow, // ->
    op_dot, // .
    op_backtick, // ` (power operator in HolyC)
    op_question, // ?
    op_ellipsis, // ...

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
    hash, // # (preprocessor)

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

/// Keyword map for fast lookup
const KeywordMap = std.StaticStringMap(TokenType);

/// All HolyC keywords mapped to their token types
const keywords = KeywordMap.initComptime(.{
    // Type keywords
    .{ "I0", .keyword_i0 },
    .{ "I8", .keyword_i8 },
    .{ "I16", .keyword_i16 },
    .{ "I32", .keyword_i32 },
    .{ "I64", .keyword_i64 },
    .{ "U0", .keyword_u0 },
    .{ "U8", .keyword_u8 },
    .{ "U16", .keyword_u16 },
    .{ "U32", .keyword_u32 },
    .{ "U64", .keyword_u64 },
    .{ "F64", .keyword_f64 },

    // Control flow
    .{ "if", .keyword_if },
    .{ "else", .keyword_else },
    .{ "while", .keyword_while },
    .{ "for", .keyword_for },
    .{ "do", .keyword_do },
    .{ "switch", .keyword_switch },
    .{ "case", .keyword_case },
    .{ "default", .keyword_default },
    .{ "break", .keyword_break },
    .{ "return", .keyword_return },
    .{ "goto", .keyword_goto },

    // Class/type related
    .{ "class", .keyword_class },
    .{ "union", .keyword_union },
    .{ "sizeof", .keyword_sizeof },
    .{ "offset", .keyword_offset },
    .{ "lastclass", .keyword_lastclass },

    // Exception handling
    .{ "try", .keyword_try },
    .{ "catch", .keyword_catch },

    // Assembly
    .{ "asm", .keyword_asm },

    // Linkage/visibility
    .{ "extern", .keyword_extern },
    .{ "import", .keyword_import },
    .{ "public", .keyword_public },
    .{ "static", .keyword_static },
    .{ "_extern", .keyword__extern },
    .{ "_import", .keyword__import },
    .{ "_intern", .keyword__intern },

    // Function attributes
    .{ "interrupt", .keyword_interrupt },
    .{ "haserrcode", .keyword_haserrcode },
    .{ "argpop", .keyword_argpop },
    .{ "noargpop", .keyword_noargpop },
    .{ "lock", .keyword_lock },

    // Register hints
    .{ "reg", .keyword_reg },
    .{ "noreg", .keyword_noreg },

    // Preprocessor
    .{ "define", .keyword_define },
    .{ "defined", .keyword_defined },
    .{ "include", .keyword_include },
    .{ "ifdef", .keyword_ifdef },
    .{ "ifndef", .keyword_ifndef },
    .{ "ifaot", .keyword_ifaot },
    .{ "ifjit", .keyword_ifjit },
    .{ "endif", .keyword_endif },
    .{ "assert", .keyword_assert },
    .{ "exe", .keyword_exe },

    // Block markers
    .{ "start", .keyword_start },
    .{ "end", .keyword_end },

    // Special
    .{ "no_warn", .keyword_no_warn },
    .{ "help_file", .keyword_help_file },
    .{ "help_index", .keyword_help_index },

    // Assembly directives (uppercase)
    .{ "ALIGN", .keyword_align },
    .{ "ORG", .keyword_org },
    .{ "BINFILE", .keyword_binfile },
    .{ "DU8", .keyword_du8 },
    .{ "DU16", .keyword_du16 },
    .{ "DU32", .keyword_du32 },
    .{ "DU64", .keyword_du64 },
    .{ "DUP", .keyword_dup },
    .{ "USE16", .keyword_use16 },
    .{ "USE32", .keyword_use32 },
    .{ "USE64", .keyword_use64 },
    .{ "LIST", .keyword_list },
    .{ "NOLIST", .keyword_nolist },
});

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
        if (isIdentifierStart(c)) {
            return self.scanIdentifier(token_line, token_column);
        }

        // Number literals
        if (isDigit(c)) {
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
            '+' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '+') {
                        self.advance();
                        return self.makeToken(.op_plus_plus, self.position - 2, token_line, token_column);
                    }
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_plus_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_plus, self.position - 1, token_line, token_column);
            },
            '-' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '-') {
                        self.advance();
                        return self.makeToken(.op_minus_minus, self.position - 2, token_line, token_column);
                    }
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_minus_equal, self.position - 2, token_line, token_column);
                    }
                    if (next == '>') {
                        self.advance();
                        return self.makeToken(.op_arrow, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_minus, self.position - 1, token_line, token_column);
            },
            '*' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_star_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_star, self.position - 1, token_line, token_column);
            },
            '/' => {
                // Check for comments before treating as division operator
                if (self.position + 1 < self.source.len) {
                    const next = self.source[self.position + 1];
                    if (next == '/') {
                        // Line comment - skip until end of line
                        self.skipLineComment();
                        return self.nextToken(); // Recursively get next token
                    } else if (next == '*') {
                        // Block comment - skip until */
                        self.skipBlockComment();
                        return self.nextToken(); // Recursively get next token
                    }
                }

                self.advance();
                if (self.peek()) |next| {
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_slash_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_slash, self.position - 1, token_line, token_column);
            },
            '%' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_percent_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_percent, self.position - 1, token_line, token_column);
            },
            '&' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '&') {
                        self.advance();
                        return self.makeToken(.op_ampersand_ampersand, self.position - 2, token_line, token_column);
                    }
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_ampersand_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_ampersand, self.position - 1, token_line, token_column);
            },
            '|' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '|') {
                        self.advance();
                        return self.makeToken(.op_pipe_pipe, self.position - 2, token_line, token_column);
                    }
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_pipe_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_pipe, self.position - 1, token_line, token_column);
            },
            '^' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '^') {
                        self.advance();
                        return self.makeToken(.op_caret_caret, self.position - 2, token_line, token_column);
                    }
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_caret_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_caret, self.position - 1, token_line, token_column);
            },
            '~' => return self.makeSingleCharToken(.op_tilde, token_line, token_column),
            '!' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_not_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_exclamation, self.position - 1, token_line, token_column);
            },
            '<' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_less_equal, self.position - 2, token_line, token_column);
                    }
                    if (next == '<') {
                        self.advance();
                        // Check for <<=
                        if (self.peek()) |next2| {
                            if (next2 == '=') {
                                self.advance();
                                return self.makeToken(.op_less_less_equal, self.position - 3, token_line, token_column);
                            }
                        }
                        return self.makeToken(.op_less_less, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_less, self.position - 1, token_line, token_column);
            },
            '>' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_greater_equal, self.position - 2, token_line, token_column);
                    }
                    if (next == '>') {
                        self.advance();
                        // Check for >>=
                        if (self.peek()) |next2| {
                            if (next2 == '=') {
                                self.advance();
                                return self.makeToken(.op_greater_greater_equal, self.position - 3, token_line, token_column);
                            }
                        }
                        return self.makeToken(.op_greater_greater, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_greater, self.position - 1, token_line, token_column);
            },
            '=' => {
                self.advance();
                if (self.peek()) |next| {
                    if (next == '=') {
                        self.advance();
                        return self.makeToken(.op_equal_equal, self.position - 2, token_line, token_column);
                    }
                }
                return self.makeToken(.op_equal, self.position - 1, token_line, token_column);
            },
            '.' => {
                self.advance();
                // Check for ... (ellipsis)
                if (self.peek()) |next| {
                    if (next == '.') {
                        if (self.peekAhead(1)) |next2| {
                            if (next2 == '.') {
                                self.advance();
                                self.advance();
                                return self.makeToken(.op_ellipsis, self.position - 3, token_line, token_column);
                            }
                        }
                    }
                }
                return self.makeToken(.op_dot, self.position - 1, token_line, token_column);
            },
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
            '#' => return self.makeSingleCharToken(.hash, token_line, token_column),
            else => {},
        }

        // TODO: Literals

        // Invalid character
        self.advance();
        return Token{
            .type = .invalid,
            .lexeme = self.source[self.position - 1 .. self.position],
            .line = token_line,
            .column = token_column,
        };
    }

    /// Scan an identifier or keyword
    fn scanIdentifier(self: *Lexer, token_line: usize, token_column: usize) Token {
        const start = self.position;

        // Consume identifier characters
        while (self.position < self.source.len and isIdentifierContinue(self.source[self.position])) {
            self.advance();
        }

        const lexeme = self.source[start..self.position];

        // Check if it's a keyword
        const token_type = getKeyword(lexeme) orelse .identifier;
        return self.makeToken(token_type, start, token_line, token_column);
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

    /// Check if a string is a keyword and return its token type
    fn getKeyword(str: []const u8) ?TokenType {
        return keywords.get(str);
    }

    /// Check if character can start an identifier
    fn isIdentifierStart(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == '_';
    }

    /// Check if character can continue an identifier
    fn isIdentifierContinue(c: u8) bool {
        return isIdentifierStart(c) or (c >= '0' and c <= '9');
    }

    /// Check if character is a digit
    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    /// Check if character is a hex digit
    fn isHexDigit(c: u8) bool {
        return (c >= '0' and c <= '9') or
            (c >= 'a' and c <= 'f') or
            (c >= 'A' and c <= 'F');
    }

    /// Check if character is a binary digit
    fn isBinaryDigit(c: u8) bool {
        return c == '0' or c == '1';
    }

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
                    if (isHexDigit(c) or c == '_') {
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
                    if (isBinaryDigit(c) or c == '_') {
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
            if (isDigit(c) or c == '_') {
                self.advance();
            } else if (c == '.' and !has_dot) {
                // Check if this is a decimal point (not an ellipsis or field access)
                if (self.position + 1 < self.source.len) {
                    const next_char = self.source[self.position + 1];
                    if (isDigit(next_char)) {
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
                    if (isDigit(exp_c) or exp_c == '_') {
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

test "keyword lookup" {
    const testing = std.testing;

    // Test type keywords
    try testing.expect(Lexer.getKeyword("I64").? == .keyword_i64);
    try testing.expect(Lexer.getKeyword("U8").? == .keyword_u8);
    try testing.expect(Lexer.getKeyword("F64").? == .keyword_f64);

    // Test control flow keywords
    try testing.expect(Lexer.getKeyword("if").? == .keyword_if);
    try testing.expect(Lexer.getKeyword("while").? == .keyword_while);
    try testing.expect(Lexer.getKeyword("return").? == .keyword_return);

    // Test special keywords
    try testing.expect(Lexer.getKeyword("interrupt").? == .keyword_interrupt);
    try testing.expect(Lexer.getKeyword("extern").? == .keyword_extern);
    try testing.expect(Lexer.getKeyword("reg").? == .keyword_reg);
    try testing.expect(Lexer.getKeyword("goto").? == .keyword_goto);

    // Test assembly keywords
    try testing.expect(Lexer.getKeyword("ALIGN").? == .keyword_align);
    try testing.expect(Lexer.getKeyword("DU64").? == .keyword_du64);

    // Test non-keywords (including library-defined identifiers)
    try testing.expect(Lexer.getKeyword("notakeyword") == null);
    try testing.expect(Lexer.getKeyword("foo") == null);
    try testing.expect(Lexer.getKeyword("Bool") == null); // Library type, not keyword
    try testing.expect(Lexer.getKeyword("TRUE") == null); // Library constant, not keyword
    try testing.expect(Lexer.getKeyword("FALSE") == null); // Library constant, not keyword
    try testing.expect(Lexer.getKeyword("NULL") == null); // Library constant, not keyword
}

test "identifier helpers" {
    const testing = std.testing;

    // Test identifier start
    try testing.expect(Lexer.isIdentifierStart('a'));
    try testing.expect(Lexer.isIdentifierStart('Z'));
    try testing.expect(Lexer.isIdentifierStart('_'));
    try testing.expect(!Lexer.isIdentifierStart('0'));
    try testing.expect(!Lexer.isIdentifierStart('$'));

    // Test identifier continue
    try testing.expect(Lexer.isIdentifierContinue('a'));
    try testing.expect(Lexer.isIdentifierContinue('Z'));
    try testing.expect(Lexer.isIdentifierContinue('_'));
    try testing.expect(Lexer.isIdentifierContinue('0'));
    try testing.expect(Lexer.isIdentifierContinue('9'));
    try testing.expect(!Lexer.isIdentifierContinue('$'));
    try testing.expect(!Lexer.isIdentifierContinue(' '));
}

test "scan simple identifier" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "foo";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .identifier);
    try testing.expectEqualStrings("foo", token.lexeme);
    try testing.expect(token.line == 1);
    try testing.expect(token.column == 1);
}

test "scan identifier with numbers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "var123";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .identifier);
    try testing.expectEqualStrings("var123", token.lexeme);
}

test "scan identifier with underscores" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "_my_var_";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .identifier);
    try testing.expectEqualStrings("_my_var_", token.lexeme);
}

test "scan type keywords" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = .{
        .{ "I64", TokenType.keyword_i64 },
        .{ "U8", TokenType.keyword_u8 },
        .{ "F64", TokenType.keyword_f64 },
        .{ "U0", TokenType.keyword_u0 },
        .{ "I32", TokenType.keyword_i32 },
    };

    inline for (test_cases) |case| {
        var lexer = Lexer.init(allocator, case[0]);
        const token = try lexer.nextToken();
        try testing.expect(token.type == case[1]);
        try testing.expectEqualStrings(case[0], token.lexeme);
    }
}

test "scan control flow keywords" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = .{
        .{ "if", TokenType.keyword_if },
        .{ "else", TokenType.keyword_else },
        .{ "while", TokenType.keyword_while },
        .{ "for", TokenType.keyword_for },
        .{ "return", TokenType.keyword_return },
        .{ "break", TokenType.keyword_break },
        .{ "goto", TokenType.keyword_goto },
    };

    inline for (test_cases) |case| {
        var lexer = Lexer.init(allocator, case[0]);
        const token = try lexer.nextToken();
        try testing.expect(token.type == case[1]);
        try testing.expectEqualStrings(case[0], token.lexeme);
    }
}

test "scan special keywords" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = .{
        .{ "interrupt", TokenType.keyword_interrupt },
        .{ "extern", TokenType.keyword_extern },
        .{ "public", TokenType.keyword_public },
        .{ "reg", TokenType.keyword_reg },
        .{ "noreg", TokenType.keyword_noreg },
        .{ "asm", TokenType.keyword_asm },
    };

    inline for (test_cases) |case| {
        var lexer = Lexer.init(allocator, case[0]);
        const token = try lexer.nextToken();
        try testing.expect(token.type == case[1]);
        try testing.expectEqualStrings(case[0], token.lexeme);
    }
}

test "case sensitivity - keywords vs identifiers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // I64 is a keyword (uppercase)
    var lexer1 = Lexer.init(allocator, "I64");
    const tok1 = try lexer1.nextToken();
    try testing.expect(tok1.type == .keyword_i64);

    // i64 is NOT a keyword (lowercase) - should be identifier
    var lexer2 = Lexer.init(allocator, "i64");
    const tok2 = try lexer2.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("i64", tok2.lexeme);

    // if is a keyword (lowercase)
    var lexer3 = Lexer.init(allocator, "if");
    const tok3 = try lexer3.nextToken();
    try testing.expect(tok3.type == .keyword_if);

    // IF is NOT a keyword (uppercase) - should be identifier
    var lexer4 = Lexer.init(allocator, "IF");
    const tok4 = try lexer4.nextToken();
    try testing.expect(tok4.type == .identifier);
    try testing.expectEqualStrings("IF", tok4.lexeme);
}

test "scan multiple tokens" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "I64 x";
    var lexer = Lexer.init(allocator, source);

    // First token: I64
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_i64);
    try testing.expectEqualStrings("I64", tok1.lexeme);

    // Second token: x
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("x", tok2.lexeme);

    // EOF
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .eof);
}

test "special identifiers are not keywords" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // pad, reserved, _anon_ should be identifiers, not keywords
    const test_cases = [_][]const u8{ "pad", "reserved", "_anon_" };

    for (test_cases) |name| {
        var lexer = Lexer.init(allocator, name);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .identifier);
        try testing.expectEqualStrings(name, token.lexeme);
    }
}

test "single-character operators" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = .{
        .{ "+", TokenType.op_plus },
        .{ "-", TokenType.op_minus },
        .{ "*", TokenType.op_star },
        .{ "/", TokenType.op_slash },
        .{ "%", TokenType.op_percent },
        .{ "&", TokenType.op_ampersand },
        .{ "|", TokenType.op_pipe },
        .{ "^", TokenType.op_caret },
        .{ "~", TokenType.op_tilde },
        .{ "!", TokenType.op_exclamation },
        .{ "<", TokenType.op_less },
        .{ ">", TokenType.op_greater },
        .{ "=", TokenType.op_equal },
        .{ ".", TokenType.op_dot },
        .{ "`", TokenType.op_backtick },
        .{ "?", TokenType.op_question },
    };

    inline for (test_cases) |case| {
        var lexer = Lexer.init(allocator, case[0]);
        const token = try lexer.nextToken();
        try testing.expect(token.type == case[1]);
        try testing.expectEqualStrings(case[0], token.lexeme);
    }
}

test "two-character operators" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = .{
        .{ "==", TokenType.op_equal_equal },
        .{ "!=", TokenType.op_not_equal },
        .{ "<=", TokenType.op_less_equal },
        .{ ">=", TokenType.op_greater_equal },
        .{ "<<", TokenType.op_less_less },
        .{ ">>", TokenType.op_greater_greater },
        .{ "&&", TokenType.op_ampersand_ampersand },
        .{ "||", TokenType.op_pipe_pipe },
        .{ "^^", TokenType.op_caret_caret },
        .{ "++", TokenType.op_plus_plus },
        .{ "--", TokenType.op_minus_minus },
        .{ "+=", TokenType.op_plus_equal },
        .{ "-=", TokenType.op_minus_equal },
        .{ "*=", TokenType.op_star_equal },
        .{ "/=", TokenType.op_slash_equal },
        .{ "%=", TokenType.op_percent_equal },
        .{ "&=", TokenType.op_ampersand_equal },
        .{ "|=", TokenType.op_pipe_equal },
        .{ "^=", TokenType.op_caret_equal },
        .{ "->", TokenType.op_arrow },
    };

    inline for (test_cases) |case| {
        var lexer = Lexer.init(allocator, case[0]);
        const token = try lexer.nextToken();
        try testing.expect(token.type == case[1]);
        try testing.expectEqualStrings(case[0], token.lexeme);
    }
}

test "three-character operators" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = .{
        .{ "<<=", TokenType.op_less_less_equal },
        .{ ">>=", TokenType.op_greater_greater_equal },
        .{ "...", TokenType.op_ellipsis },
    };

    inline for (test_cases) |case| {
        var lexer = Lexer.init(allocator, case[0]);
        const token = try lexer.nextToken();
        try testing.expect(token.type == case[1]);
        try testing.expectEqualStrings(case[0], token.lexeme);
    }
}

test "delimiters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = .{
        .{ "(", TokenType.lparen },
        .{ ")", TokenType.rparen },
        .{ "{", TokenType.lbrace },
        .{ "}", TokenType.rbrace },
        .{ "[", TokenType.lbracket },
        .{ "]", TokenType.rbracket },
        .{ ";", TokenType.semicolon },
        .{ ",", TokenType.comma },
        .{ ":", TokenType.colon },
        .{ "#", TokenType.hash },
    };

    inline for (test_cases) |case| {
        var lexer = Lexer.init(allocator, case[0]);
        const token = try lexer.nextToken();
        try testing.expect(token.type == case[1]);
        try testing.expectEqualStrings(case[0], token.lexeme);
    }
}

test "operator disambiguation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test that + is not confused with ++
    var lexer1 = Lexer.init(allocator, "+ x");
    const tok1 = try lexer1.nextToken();
    try testing.expect(tok1.type == .op_plus);
    try testing.expectEqualStrings("+", tok1.lexeme);

    // Test that ++ is recognized
    var lexer2 = Lexer.init(allocator, "++");
    const tok2 = try lexer2.nextToken();
    try testing.expect(tok2.type == .op_plus_plus);
    try testing.expectEqualStrings("++", tok2.lexeme);

    // Test that < is not confused with << or <=
    var lexer3 = Lexer.init(allocator, "< x");
    const tok3 = try lexer3.nextToken();
    try testing.expect(tok3.type == .op_less);
    try testing.expectEqualStrings("<", tok3.lexeme);

    // Test that << is not confused with <<=
    var lexer4 = Lexer.init(allocator, "<< x");
    const tok4 = try lexer4.nextToken();
    try testing.expect(tok4.type == .op_less_less);
    try testing.expectEqualStrings("<<", tok4.lexeme);

    // Test that <<= is recognized
    var lexer5 = Lexer.init(allocator, "<<=");
    const tok5 = try lexer5.nextToken();
    try testing.expect(tok5.type == .op_less_less_equal);
    try testing.expectEqualStrings("<<=", tok5.lexeme);
}

test "expression with operators" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "x + y * 2";
    var lexer = Lexer.init(allocator, source);

    // x
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .identifier);
    try testing.expectEqualStrings("x", tok1.lexeme);

    // +
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .op_plus);
    try testing.expectEqualStrings("+", tok2.lexeme);

    // y
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .identifier);
    try testing.expectEqualStrings("y", tok3.lexeme);

    // *
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .op_star);
    try testing.expectEqualStrings("*", tok4.lexeme);

    // 2
    const tok5 = try lexer.nextToken();
    try testing.expect(tok5.type == .integer_literal);
    try testing.expectEqualStrings("2", tok5.lexeme);
}

test "HolyC power operator" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // The backtick ` is HolyC's power operator: 2`8 = 256
    const source = "2`8";
    var lexer = Lexer.init(allocator, source);

    // 2
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .integer_literal);
    try testing.expectEqualStrings("2", tok1.lexeme);

    // `
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .op_backtick);
    try testing.expectEqualStrings("`", tok2.lexeme);

    // 8
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .integer_literal);
    try testing.expectEqualStrings("8", tok3.lexeme);
}

test "pointer arrow operator" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "ptr->field";
    var lexer = Lexer.init(allocator, source);

    // ptr
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .identifier);
    try testing.expectEqualStrings("ptr", tok1.lexeme);

    // ->
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .op_arrow);
    try testing.expectEqualStrings("->", tok2.lexeme);

    // field
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .identifier);
    try testing.expectEqualStrings("field", tok3.lexeme);
}

test "decimal integer literals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{ "0", "42", "123", "999" };

    for (test_cases) |num| {
        var lexer = Lexer.init(allocator, num);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .integer_literal);
        try testing.expectEqualStrings(num, token.lexeme);
    }
}

test "hexadecimal integer literals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{ "0x0", "0xFF", "0x1234", "0xABCD", "0xabcd" };

    for (test_cases) |num| {
        var lexer = Lexer.init(allocator, num);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .integer_literal);
        try testing.expectEqualStrings(num, token.lexeme);
    }
}

test "binary integer literals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{ "0b0", "0b1", "0b1010", "0b11111111" };

    for (test_cases) |num| {
        var lexer = Lexer.init(allocator, num);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .integer_literal);
        try testing.expectEqualStrings(num, token.lexeme);
    }
}

test "integer literals with underscores" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{ "1_000", "1_000_000", "0xFF_FF", "0b1111_0000" };

    for (test_cases) |num| {
        var lexer = Lexer.init(allocator, num);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .integer_literal);
        try testing.expectEqualStrings(num, token.lexeme);
    }
}

test "float literals" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{ "0.0", "3.14", "123.456", "0.5" };

    for (test_cases) |num| {
        var lexer = Lexer.init(allocator, num);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .float_literal);
        try testing.expectEqualStrings(num, token.lexeme);
    }
}

test "float literals with scientific notation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{ "1e10", "3.14e-5", "2.5E+3", "1.0e0" };

    for (test_cases) |num| {
        var lexer = Lexer.init(allocator, num);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .float_literal);
        try testing.expectEqualStrings(num, token.lexeme);
    }
}

test "number followed by operator" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "42+3";
    var lexer = Lexer.init(allocator, source);

    // 42
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .integer_literal);
    try testing.expectEqualStrings("42", tok1.lexeme);

    // +
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .op_plus);
    try testing.expectEqualStrings("+", tok2.lexeme);

    // 3
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .integer_literal);
    try testing.expectEqualStrings("3", tok3.lexeme);
}

test "complete expression" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "I64 x = 42 + y * 0xFF;";
    var lexer = Lexer.init(allocator, source);

    // I64
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_i64);

    // x
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);

    // =
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .op_equal);

    // 42
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .integer_literal);
    try testing.expectEqualStrings("42", tok4.lexeme);

    // +
    const tok5 = try lexer.nextToken();
    try testing.expect(tok5.type == .op_plus);

    // y
    const tok6 = try lexer.nextToken();
    try testing.expect(tok6.type == .identifier);

    // *
    const tok7 = try lexer.nextToken();
    try testing.expect(tok7.type == .op_star);

    // 0xFF
    const tok8 = try lexer.nextToken();
    try testing.expect(tok8.type == .integer_literal);
    try testing.expectEqualStrings("0xFF", tok8.lexeme);

    // ;
    const tok9 = try lexer.nextToken();
    try testing.expect(tok9.type == .semicolon);
}

test "line comments are skipped" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source =
        \\// This is a comment
        \\I64 x
    ;
    var lexer = Lexer.init(allocator, source);

    // Should skip the comment and get I64
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_i64);

    // x
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
}

test "line comment at end of line" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "I64 x; // variable declaration";
    var lexer = Lexer.init(allocator, source);

    // I64
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_i64);

    // x
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);

    // ;
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .semicolon);

    // EOF (comment should be skipped)
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .eof);
}

test "block comments are skipped" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "/* This is a block comment */ I64 x";
    var lexer = Lexer.init(allocator, source);

    // Should skip the comment and get I64
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_i64);

    // x
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
}

test "multiline block comments" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source =
        \\/*
        \\ * This is a multi-line
        \\ * block comment
        \\ */
        \\I64 x
    ;
    var lexer = Lexer.init(allocator, source);

    // Should skip the comment and get I64
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_i64);
    try testing.expect(tok1.line == 5); // Should be on line 5 after multi-line comment

    // x
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
}

test "block comment in expression" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "x /* comment */ + /* another */ y";
    var lexer = Lexer.init(allocator, source);

    // x
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .identifier);
    try testing.expectEqualStrings("x", tok1.lexeme);

    // +
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .op_plus);

    // y
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .identifier);
    try testing.expectEqualStrings("y", tok3.lexeme);
}

test "division operator not confused with comment" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "x / y";
    var lexer = Lexer.init(allocator, source);

    // x
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .identifier);

    // /
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .op_slash);
    try testing.expectEqualStrings("/", tok2.lexeme);

    // y
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .identifier);
}

test "simple string literal" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "\"Hello, World!\"";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .string_literal);
    try testing.expectEqualStrings("\"Hello, World!\"", token.lexeme);
}

test "string with escape sequences" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "\"Hello\\nWorld\\t!\"";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .string_literal);
    try testing.expectEqualStrings("\"Hello\\nWorld\\t!\"", token.lexeme);
}

test "empty string" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "\"\"";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .string_literal);
    try testing.expectEqualStrings("\"\"", token.lexeme);
}

test "string in expression" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "x = \"test\"";
    var lexer = Lexer.init(allocator, source);

    // x
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .identifier);

    // =
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .op_equal);

    // "test"
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .string_literal);
    try testing.expectEqualStrings("\"test\"", tok3.lexeme);
}

test "simple char literal" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "'A'";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .char_literal);
    try testing.expectEqualStrings("'A'", token.lexeme);
}

test "char literal with escape sequence" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "'\\n'";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .char_literal);
    try testing.expectEqualStrings("'\\n'", token.lexeme);
}

test "multi-character constant - HolyC feature" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // HolyC allows multi-character constants like 'Hello'
    // They represent packed integers
    const source = "'Hello'";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .char_literal);
    try testing.expectEqualStrings("'Hello'", token.lexeme);
}

test "multi-character constant - short" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "'OK'";
    var lexer = Lexer.init(allocator, source);

    const token = try lexer.nextToken();
    try testing.expect(token.type == .char_literal);
    try testing.expectEqualStrings("'OK'", token.lexeme);
}

test "tokenize complete HolyC program" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source =
        \\// Simple Hello World in HolyC
        \\U0 Main() {
        \\    "Hello, World!\n";
        \\}
    ;
    var lexer = Lexer.init(allocator, source);

    // U0
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_u0);

    // Main
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("Main", tok2.lexeme);

    // (
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .lparen);

    // )
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .rparen);

    // {
    const tok5 = try lexer.nextToken();
    try testing.expect(tok5.type == .lbrace);

    // "Hello, World!\n"
    const tok6 = try lexer.nextToken();
    try testing.expect(tok6.type == .string_literal);

    // ;
    const tok7 = try lexer.nextToken();
    try testing.expect(tok7.type == .semicolon);

    // }
    const tok8 = try lexer.nextToken();
    try testing.expect(tok8.type == .rbrace);

    // EOF
    const tok9 = try lexer.nextToken();
    try testing.expect(tok9.type == .eof);
}

test "complex expression with all features" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source =
        \\/* Multi-line comment
        \\ * with documentation */
        \\I64 factorial(I64 n) {
        \\    if (n <= 1) return 1; // base case
        \\    return n * factorial(n - 1);
        \\}
    ;
    var lexer = Lexer.init(allocator, source);

    // I64
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_i64);

    // factorial
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("factorial", tok2.lexeme);

    // (
    _ = try lexer.nextToken();

    // I64
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .keyword_i64);

    // n
    const tok5 = try lexer.nextToken();
    try testing.expect(tok5.type == .identifier);
    try testing.expectEqualStrings("n", tok5.lexeme);

    // We could continue, but this validates the key features
}

test "Bool, TRUE, FALSE, NULL are identifiers, not keywords" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // These are defined in the HolyC standard library, not language keywords
    const test_cases = [_][]const u8{ "Bool", "TRUE", "FALSE", "NULL" };

    for (test_cases) |name| {
        var lexer = Lexer.init(allocator, name);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .identifier);
        try testing.expectEqualStrings(name, token.lexeme);
    }
}

test "Bool declaration treated as regular identifier" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "Bool flag = TRUE;";
    var lexer = Lexer.init(allocator, source);

    // Bool - identifier, not keyword
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .identifier);
    try testing.expectEqualStrings("Bool", tok1.lexeme);

    // flag
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);

    // =
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .op_equal);

    // TRUE - identifier, not keyword
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .identifier);
    try testing.expectEqualStrings("TRUE", tok4.lexeme);

    // ;
    const tok5 = try lexer.nextToken();
    try testing.expect(tok5.type == .semicolon);
}
