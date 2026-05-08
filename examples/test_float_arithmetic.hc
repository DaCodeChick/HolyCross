// Test float arithmetic operations

U0 TestFloatArithmetic() {
    F64 a = 10.5;
    F64 b = 3.2;
    
    F64 sum = a + b;      // Should be 13.7
    F64 diff = a - b;     // Should be 7.3
    F64 prod = a * b;     // Should be 33.6
    F64 quot = a / b;     // Should be ~3.28
}

U0 Main() {
    TestFloatArithmetic;
}

Main;
