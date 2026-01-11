//! Lexer tests - imports all test modules
//!
//! Test modules organized by functionality:
//! - lexer_keyword_tests: Keyword recognition and identifiers
//! - lexer_operator_tests: Operators and delimiters
//! - lexer_literal_tests: Integer, float, string, and char literals
//! - lexer_advanced_tests: Comments, complete programs, preprocessor

// Import all test modules
test {
    _ = @import("lexer_keyword_tests.zig");
    _ = @import("lexer_operator_tests.zig");
    _ = @import("lexer_literal_tests.zig");
    _ = @import("lexer_advanced_tests.zig");
}
