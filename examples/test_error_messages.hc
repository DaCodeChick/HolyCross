// Test that error messages show readable type names

I64 Add(I64 a, I64 b) {
    return a + b;
}

I32 Test() {
    // Missing return statement - should show "Function 'Test' with return type 'I32' is missing return statement"
}

U0 Main() {
    // Wrong argument count
    I64 result = Add(10);  // Should show "Function 'Add' expects 2 argument(s), but got 1"
}
