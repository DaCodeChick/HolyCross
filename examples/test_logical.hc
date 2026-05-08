// Test logical and bitwise NOT operations

U0 TestLogical() {
    // Test logical NOT
    I64 a = 0;
    I64 b = !a;     // Should be 1
    
    I64 c = 5;
    I64 d = !c;     // Should be 0
    
    // Test logical AND
    I64 e = 1 && 1; // Should be 1
    I64 f = 1 && 0; // Should be 0
    I64 g = 0 && 1; // Should be 0
    
    // Test logical OR
    I64 h = 0 || 0; // Should be 0
    I64 i = 1 || 0; // Should be 1
    I64 j = 0 || 1; // Should be 1
}

U0 TestBitwiseNot() {
    // Test bitwise NOT
    I64 a = 0;
    I64 b = ~a;     // Should be -1 (all bits set)
    
    I64 c = 0b1111;
    I64 d = ~c;     // Should flip all bits
}

U0 Main() {
    TestLogical;
    TestBitwiseNot;
}

Main;
