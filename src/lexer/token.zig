const std = @import("std");

/// Token types for HolyC lexer
/// Complete list based on TempleOS Compiler/OpCodes.DD and CompilerA.HH
pub const TokenType = enum {
    // Literals
    integer_literal,
    float_literal,
    string_literal,
    char_literal,

    // Type Keywords (I0-I64, U0-U64, F64, Bool)
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
    keyword_bool, // Boolean type (uses I64 internally)

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
