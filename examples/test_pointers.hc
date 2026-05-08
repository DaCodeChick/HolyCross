// Test pointer operations

U0 TestPointers() {
    I64 x = 42;
    I64* ptr = &x;
    I64 y = *ptr;  // Should be 42
    
    *ptr = 100;  // Modify x through pointer
    I64 z = x;   // Should be 100
}

U0 Main() {
    TestPointers;
}

Main;
