//! Parser tests - imports all test modules
//!
//! Test modules organized by functionality:
//! - parser_expression_tests: Literals, binary/unary operators, precedence
//! - parser_postfix_tests: Function calls, array subscripts, member access
//! - parser_type_tests: Primitives, pointers, arrays, named types
//! - parser_statement_tests: Variable declarations, assignments, blocks
//! - parser_control_flow_tests: If, while, for, switch, goto, try-catch
//! - parser_declaration_tests: Functions, classes, unions, globals

// Import all test modules
test {
    _ = @import("parser_expression_tests.zig");
    _ = @import("parser_postfix_tests.zig");
    _ = @import("parser_type_tests.zig");
    _ = @import("parser_statement_tests.zig");
    _ = @import("parser_control_flow_tests.zig");
    _ = @import("parser_declaration_tests.zig");
}
