//! Semantic analyzer tests - imports all test modules
//!
//! Test modules organized by functionality:
//! - analyzer_basic_tests: Initialization and empty programs
//! - analyzer_declaration_tests: Functions, classes, unions, globals
//! - analyzer_control_flow_tests: Loops, break, goto, labels, switch
//! - analyzer_function_tests: Function calls, returns, parameters, scoping
//! - analyzer_reachability_tests: Unreachable code detection

// Import all test modules
test {
    _ = @import("test_helpers.zig");
    _ = @import("analyzer_basic_tests.zig");
    _ = @import("analyzer_declaration_tests.zig");
    _ = @import("analyzer_control_flow_tests.zig");
    _ = @import("analyzer_function_tests.zig");
    _ = @import("analyzer_reachability_tests.zig");
}
