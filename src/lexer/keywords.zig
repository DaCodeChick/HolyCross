const std = @import("std");
const TokenType = @import("token.zig").TokenType;

/// Keyword map for fast lookup
const KeywordMap = std.StaticStringMap(TokenType);

/// All HolyC keywords mapped to their token types (72 total)
pub const keywords = KeywordMap.initComptime(.{
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
    .{ "Bool", .keyword_bool },

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

/// Get the keyword token type for a given string, if it exists
pub fn getKeyword(text: []const u8) ?TokenType {
    return keywords.get(text);
}
