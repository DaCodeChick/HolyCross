/// Character classification and helper functions for lexer
/// These are pure functions that don't depend on Lexer state
/// Check if character can start an identifier
pub fn isIdentifierStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        c == '_';
}

/// Check if character can continue an identifier
pub fn isIdentifierContinue(c: u8) bool {
    return isIdentifierStart(c) or (c >= '0' and c <= '9');
}

/// Check if character is a digit
pub fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

/// Check if character is a hex digit
pub fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or
        (c >= 'a' and c <= 'f') or
        (c >= 'A' and c <= 'F');
}

/// Check if character is a binary digit
pub fn isBinaryDigit(c: u8) bool {
    return c == '0' or c == '1';
}

/// Check if character is whitespace
pub fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}
