// Test if/else statements
I64 Max(I64 a, I64 b) {
    if (a > b) {
        return a;
    } else {
        return b;
    }
}

I64 Min(I64 a, I64 b) {
    if (a < b) {
        return a;
    }
    return b;
}

U0 Main() {
    I64 x = Max(10, 20);  // Should return 20
    I64 y = Max(30, 15);  // Should return 30
    I64 z = Min(5, 8);    // Should return 5
    "If/else test completed\n";
}
