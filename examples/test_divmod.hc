// Test division and modulo operations

U0 TestDivMod() {
    I64 a = 100;
    I64 b = 7;
    
    I64 quotient = a / b;   // Should be 14
    I64 remainder = a % b;  // Should be 2
    
    I64 c = 50;
    I64 d = 5;
    I64 result = c / d;     // Should be 10
}

U0 Main() {
    TestDivMod;
}

Main;
