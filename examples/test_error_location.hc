// Test file for error location tracking

U0 Add(I64 a, I64 b) {
    return a + b;
}

U0 Main() {
    // This should report error at line 9
    Add(5);  // Wrong argument count
}

Main;
