// Test __DIR__ macro expansion to actual directory path

// Use __DIR__ in an expression - should expand to "examples"
U0 TestDirExpansion() {
    // In this context, __DIR__ should be replaced with the actual directory
    // For examples/test_dir_expansion.hc, __DIR__ -> "examples"
}

U0 Main() {
    TestDirExpansion();
}
