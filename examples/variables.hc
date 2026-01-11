// HolyC Variable Declaration Examples
// Tests parser with various variable declarations

U0 TestSimpleDeclarations() {
    // Simple declarations (no initializer)
    I64 x;
    U32 y;
    F64 z;
    I8 byte;
    U16 word;
}

U0 TestInitializers() {
    // Declarations with initializers
    I64 count = 42;
    U32 size = 1024;
    F64 pi = 3.14159;
    I8 flag = 1;
}

U0 TestExpressions() {
    I64 a;
    I64 b;
    I64 x;
    I64 y;
    
    // Declarations with expressions
    I64 sum = a + b;
    U32 product = x * y;
    F64 average = (a + b) / 2;
}

U0 TestPointers() {
    I64 x;
    I64 data;
    
    // Pointer declarations
    I64* ptr = &x;
    U8* buffer = &data;
    
    // Pointer with null
    I64* null_ptr = 0;
}

U0 TestMultiple() {
    // Multiple similar declarations
    I64 a;
    I64 b;
    I64 c;
}

U0 TestOperators() {
    I64 value;
    U32 flags;
    I64 original;
    I64* ptr;
    
    // Declarations with various operators
    I64 shifted = value << 2;
    U32 masked = flags & 0xFF;
    I64 negated = -original;
    U8* incremented = ptr + 1;
}

U0 TestLiterals() {
    // String and char initializers
    U8* message = "Hello";
    I64 ch = 'A';
}

U0 Main() {
    TestSimpleDeclarations();
    TestInitializers();
    TestExpressions();
    TestPointers();
    TestMultiple();
    TestOperators();
    TestLiterals();
}

/*
NOTE: Array declarations like "I64 numbers[10]" are not yet supported.
This includes:
- Fixed-size arrays: I64 numbers[10]
- Unsized arrays: I64 dynamic[]
- Array of pointers: I64* ptr_array[5]
- Pointer to array: I64 (*array_ptr)[10]
*/
