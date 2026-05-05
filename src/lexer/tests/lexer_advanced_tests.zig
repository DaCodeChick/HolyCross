//! Advanced tests: comments, complete programs, preprocessor directives
const std = @import("std");
const Lexer = @import("../lexer.zig").Lexer;
const TokenType = @import("../token.zig").TokenType;
const helpers = @import("../helpers.zig");

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

test "Bool is builtin keyword; TRUE, FALSE, NULL are identifiers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Bool is now a builtin type keyword
    var lexer1 = Lexer.init(allocator, "Bool");
    const tok1 = try lexer1.nextToken();
    try testing.expect(tok1.type == .keyword_bool);
    try testing.expectEqualStrings("Bool", tok1.lexeme);

    // TRUE, FALSE, NULL are regular identifiers (not builtins)
    const test_cases = [_][]const u8{ "TRUE", "FALSE", "NULL" };

    for (test_cases) |name| {
        var lexer = Lexer.init(allocator, name);
        const token = try lexer.nextToken();
        try testing.expect(token.type == .identifier);
        try testing.expectEqualStrings(name, token.lexeme);
    }
}

test "Bool declaration as builtin type" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "Bool flag = TRUE;";
    var lexer = Lexer.init(allocator, source);

    // Bool - keyword
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_bool);
    try testing.expectEqualStrings("Bool", tok1.lexeme);

    // flag
    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);

    // =
    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .op_equal);

    // TRUE - identifier (preprocessor symbol)
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .identifier);
    try testing.expectEqualStrings("TRUE", tok4.lexeme);

    // ;
    const tok5 = try lexer.nextToken();
    try testing.expect(tok5.type == .semicolon);
}

test "preprocessor directive #define" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "#define MAX 100";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_define);
    try testing.expectEqualStrings("#define", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("MAX", tok2.lexeme);

    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .integer_literal);
    try testing.expectEqualStrings("100", tok3.lexeme);
}

test "preprocessor directive #include" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "#include \"stdio.h\"";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_include);
    try testing.expectEqualStrings("#include", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .string_literal);
    try testing.expectEqualStrings("\"stdio.h\"", tok2.lexeme);
}

test "preprocessor directive with space after #" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // C/HolyC allows space after '#': "# define" is valid
    const source = "# define VALUE 42";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_define);
    // Lexeme includes the '#', space(s), and directive name
    try testing.expectEqualStrings("# define", tok1.lexeme);
}

test "preprocessor directives #ifdef #endif" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "#ifdef DEBUG\n#endif";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_ifdef);
    try testing.expectEqualStrings("#ifdef", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("DEBUG", tok2.lexeme);

    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .keyword_endif);
    try testing.expectEqualStrings("#endif", tok3.lexeme);
}

test "preprocessor directive #ifndef" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "#ifndef GUARD_H";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_ifndef);
    try testing.expectEqualStrings("#ifndef", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("GUARD_H", tok2.lexeme);
}

test "preprocessor directives #ifaot #ifjit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "#ifaot\n#ifjit";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_ifaot);
    try testing.expectEqualStrings("#ifaot", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .keyword_ifjit);
    try testing.expectEqualStrings("#ifjit", tok2.lexeme);
}

test "preprocessor directive #assert" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "#assert x > 0";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_assert);
    try testing.expectEqualStrings("#assert", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("x", tok2.lexeme);
}

test "preprocessor directive #exe - compile-time execution" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "#exe { Print(\"Hello\"); }";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_exe);
    try testing.expectEqualStrings("#exe", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .lbrace);
}

test "preprocessor keyword 'defined' in expression" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 'defined' is used in #if expressions: #if defined(FOO)
    const source = "defined(FOO)";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_defined);
    try testing.expectEqualStrings("defined", tok1.lexeme);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .lparen);
}

test "hash alone without directive" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Just '#' without a directive name
    const source = "# ";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .hash);
    try testing.expectEqualStrings("# ", tok1.lexeme);
}

test "hash with unknown directive" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // '#' with an unrecognized directive
    const source = "#unknown";
    var lexer = Lexer.init(allocator, source);

    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .hash);
    try testing.expectEqualStrings("#unknown", tok1.lexeme);
}

test "complete preprocessor example" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source =
        \\#define TRUE 1
        \\#define FALSE 0
        \\#ifdef DEBUG
        \\  Print("Debug mode\n");
        \\#endif
    ;
    var lexer = Lexer.init(allocator, source);

    // #define TRUE 1
    const tok1 = try lexer.nextToken();
    try testing.expect(tok1.type == .keyword_define);

    const tok2 = try lexer.nextToken();
    try testing.expect(tok2.type == .identifier);
    try testing.expectEqualStrings("TRUE", tok2.lexeme);

    const tok3 = try lexer.nextToken();
    try testing.expect(tok3.type == .integer_literal);
    try testing.expectEqualStrings("1", tok3.lexeme);

    // #define FALSE 0
    const tok4 = try lexer.nextToken();
    try testing.expect(tok4.type == .keyword_define);

    const tok5 = try lexer.nextToken();
    try testing.expect(tok5.type == .identifier);
    try testing.expectEqualStrings("FALSE", tok5.lexeme);

    const tok6 = try lexer.nextToken();
    try testing.expect(tok6.type == .integer_literal);
    try testing.expectEqualStrings("0", tok6.lexeme);

    // #ifdef DEBUG
    const tok7 = try lexer.nextToken();
    try testing.expect(tok7.type == .keyword_ifdef);

    const tok8 = try lexer.nextToken();
    try testing.expect(tok8.type == .identifier);
    try testing.expectEqualStrings("DEBUG", tok8.lexeme);

    // Print
    const tok9 = try lexer.nextToken();
    try testing.expect(tok9.type == .identifier);
    try testing.expectEqualStrings("Print", tok9.lexeme);

    // ... we could continue but this validates the preprocessor handling
}
