//! Keyword recognition and identifier tests
const std = @import("std");
const Lexer = @import("../lexer.zig").Lexer;
const TokenType = @import("../token.zig").TokenType;
const helpers = @import("../helpers.zig");

test "keyword lookup" {
    const testing = std.testing;

    // Test type keywords
    try testing.expect(@import("../keywords.zig").getKeyword("I64").? == .keyword_i64);
    try testing.expect(@import("../keywords.zig").getKeyword("U8").? == .keyword_u8);
    try testing.expect(@import("../keywords.zig").getKeyword("F64").? == .keyword_f64);

    // Test control flow keywords
    try testing.expect(@import("../keywords.zig").getKeyword("if").? == .keyword_if);
    try testing.expect(@import("../keywords.zig").getKeyword("while").? == .keyword_while);
    try testing.expect(@import("../keywords.zig").getKeyword("return").? == .keyword_return);

    // Test special keywords
    try testing.expect(@import("../keywords.zig").getKeyword("interrupt").? == .keyword_interrupt);
    try testing.expect(@import("../keywords.zig").getKeyword("extern").? == .keyword_extern);
    try testing.expect(@import("../keywords.zig").getKeyword("reg").? == .keyword_reg);
    try testing.expect(@import("../keywords.zig").getKeyword("goto").? == .keyword_goto);

    // Test assembly keywords
    try testing.expect(@import("../keywords.zig").getKeyword("ALIGN").? == .keyword_align);
    try testing.expect(@import("../keywords.zig").getKeyword("DU64").? == .keyword_du64);

    // Test non-keywords (including library-defined identifiers)
    try testing.expect(@import("../keywords.zig").getKeyword("notakeyword") == null);
    try testing.expect(@import("../keywords.zig").getKeyword("foo") == null);
    try testing.expect(@import("../keywords.zig").getKeyword("Bool") == null); // Library type, not keyword
    try testing.expect(@import("../keywords.zig").getKeyword("TRUE") == null); // Library constant, not keyword
    try testing.expect(@import("../keywords.zig").getKeyword("FALSE") == null); // Library constant, not keyword
    try testing.expect(@import("../keywords.zig").getKeyword("NULL") == null); // Library constant, not keyword
}

test "identifier helpers" {
    const testing = std.testing;

    // Test identifier start
    try testing.expect(helpers.isIdentifierStart('a'));
    try testing.expect(helpers.isIdentifierStart('Z'));
    try testing.expect(helpers.isIdentifierStart('_'));
    try testing.expect(!helpers.isIdentifierStart('0'));
    try testing.expect(!helpers.isIdentifierStart('$'));

    // Test identifier continue
    try testing.expect(helpers.isIdentifierContinue('a'));
    try testing.expect(helpers.isIdentifierContinue('Z'));
    try testing.expect(helpers.isIdentifierContinue('_'));
    try testing.expect(helpers.isIdentifierContinue('0'));
    try testing.expect(helpers.isIdentifierContinue('9'));
    try testing.expect(!helpers.isIdentifierContinue('$'));
    try testing.expect(!helpers.isIdentifierContinue(' '));
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
