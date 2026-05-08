// Test simple while loop
I64 main() {
    I64 sum = 0;
    I64 i = 0;
    while (i < 5) {
        sum = sum + i;
        i = i + 1;
    }
    return sum;  // Should return 0+1+2+3+4 = 10
}
