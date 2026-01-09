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

    // Test non-keywords
    try testing.expect(Lexer.getKeyword("notakeyword") == null);
    try testing.expect(Lexer.getKeyword("foo") == null);
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
