// Test bitwise and arithmetic operations

U0 TestBitwise() {
    // Test AND
    I64 a = 0b1111;
    I64 b = 0b1010;
    I64 c = a & b;  // Should be 0b1010 = 10
    
    // Test OR
    I64 d = a | b;  // Should be 0b1111 = 15
    
    // Test XOR
    I64 e = a ^ b;  // Should be 0b0101 = 5
    
    // Test left shift
    I64 f = 5;
    I64 g = f << 2; // Should be 20
    
    // Test right shift
    I64 h = 20;
    I64 i = h >> 2; // Should be 5
    
    // Test negation
    I64 j = 10;
    I64 k = -j;     // Should be -10
}

U0 TestArithmetic() {
    // Test division
    I64 a = 100;
    I64 b = 7;
    I64 quotient = a / b;   // Should be 14
    
    // Test modulo
    I64 remainder = a % b;  // Should be 2
    
    // Test combined
    I64 c = 50;
    I64 d = 5;
    I64 result = (c / d) + (c % d); // Should be 10 + 0 = 10
}

U0 Main() {
    TestBitwise;
    TestArithmetic;
}

Main;
