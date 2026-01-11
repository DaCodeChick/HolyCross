//! Literal tokenization tests: integers, floats, strings, chars
const std = @import("std");
const Lexer = @import("../lexer.zig").Lexer;
const TokenType = @import("../token.zig").TokenType;
const helpers = @import("../helpers.zig");

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
