// Test while loops
I64 Sum10() {
    I64 i = 0;
    I64 sum = 0;
    while (i < 10) {
        sum = sum + i;
        i = i + 1;
    }
    return sum;  // Should return 45 (0+1+2+...+9)
}

U0 Main() {
    I64 result = Sum10();
    "While loop test completed\n";
}
