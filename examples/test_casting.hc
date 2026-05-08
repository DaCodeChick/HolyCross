// Test type casting

U0 TestCasting() {
    // Integer to integer casts
    I64 a = 100;
    I32 b = (I32)a;
    I8 c = (I8)b;
    U64 d = (U64)a;
    
    // Pointer casts
    I64 x = 42;
    I64* ptr = &x;
    U8* byte_ptr = (U8*)ptr;
    
    // Cast with arithmetic
    I64 result = (I64)(b + c);
}

U0 Main() {
    TestCasting;
}

Main;
