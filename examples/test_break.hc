// Test break statements in loops
I64 FindFirst(I64 n) {
    I64 i = 0;
    while (i < 100) {
        if (i == n) {
            break;
        }
        i = i + 1;
    }
    return i;
}

I64 SumUntilTen() {
    I64 sum = 0;
    I64 i = 0;
    while (1) {  // Infinite loop
        if (i >= 10) {
            break;
        }
        sum = sum + i;
        i = i + 1;
    }
    return sum;  // Should return 45 (0+1+2+...+9)
}

U0 Main() {
    I64 found = FindFirst(7);      // Should return 7
    I64 total = SumUntilTen();     // Should return 45
    "Break test completed\n";
}
