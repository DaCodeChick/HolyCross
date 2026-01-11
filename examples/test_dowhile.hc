// Test do-while loops
I64 CountDown(I64 n) {
    I64 count = 0;
    do {
        count = count + 1;
        n = n - 1;
    } while (n > 0);
    return count;
}

U0 Main() {
    I64 result = CountDown(5);  // Should return 5
    "Do-while test completed\n";
}
