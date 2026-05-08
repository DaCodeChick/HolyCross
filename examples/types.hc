// HolyC Type Examples
// Tests parser with various type declarations

U0 TestPrimitiveTypes() {
    // Primitive types
    I64 x;
    U32 y;
    F64 z;
    I8 a;
    U16 b;
}

U0 TestPointerTypes() {
    // Pointer types
    I64* ptr;
    U8** double_ptr;
    F64* float_ptr;
    
    // Nested pointers
    U8*** triple_ptr;
    I64**** quad_ptr;
}

U0 Main() {
    TestPrimitiveTypes();
    TestPointerTypes();
}

/*
NOT YET SUPPORTED:
- Array declarations: I64 arr[10]
- Named types without definition: CDate date (unless CDate is defined)
- Complex array/pointer combinations: I64* array[5], I64 (*ptr)[10]
*/

Main;
