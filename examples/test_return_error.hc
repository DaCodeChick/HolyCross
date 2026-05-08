// Test return type mismatch error

I64 GetNumber() {
    return;  // Should show "Function expects return type 'I64' but got no return value"
}

U0 Main() {
    GetNumber;
}
