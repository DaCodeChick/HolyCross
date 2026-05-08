// Test type mismatch error messages with incompatible types

I64 Add(I64 a, I64 b) {
    return a + b;
}

I64 Multiply(I64 x, I64 y) {
    return x * y;
}

U0 Main() {
    // Test: calling function with wrong argument type
    I64 result = Add(10, Multiply);  // Should show type error with function type
}
