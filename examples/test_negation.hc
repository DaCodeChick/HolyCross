// Test negation operation

U0 TestNegation() {
    I64 a = 10;
    I64 b = -a;     // Should be -10
    
    I64 c = -5;
    I64 d = -c;     // Should be 5
    
    I64 e = 0;
    I64 f = -e;     // Should be 0
}

U0 Main() {
    TestNegation;
}

Main;
