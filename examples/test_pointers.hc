// Test pointer operations
U0 Main() {
    I64 x = 42;
    I64* ptr = &x;
    I64 value = *ptr;
    *ptr = 100;
    "Pointer test completed\n";
}
