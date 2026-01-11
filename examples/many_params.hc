// Test 8 parameters - verifies stack passing (params 7-8)
// Parameters 1-6 should be in registers (RDI, RSI, RDX, RCX, R8, R9)
// Parameters 7-8 should be on stack ([rbp+16], [rbp+24])

I64 Sum8(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h) {
    return a + b + c + d + e + f + g + h;
}

U0 Main() {
    I64 result = Sum8(1, 2, 3, 4, 5, 6, 7, 8);
    // Expected result: 1+2+3+4+5+6+7+8 = 36
    "Sum of 8 parameters calculated\n";
}
