//! Operator and delimiter tokenization tests
const std = @import("std");
const Lexer = @import("../lexer.zig").Lexer;
const TokenType = @import("../token.zig").TokenType;
const helpers = @import("../helpers.zig");

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
