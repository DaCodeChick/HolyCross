// Test for loops
I64 Factorial(I64 n) {
    I64 result = 1;
    I64 i;
    for (i = 1; i <= n; i = i + 1) {
        result = result * i;
    }
    return result;
}

U0 Main() {
    I64 f5 = Factorial(5);  // Should return 120
    "For loop test completed\n";
}
