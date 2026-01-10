// HolyC Type Examples
// Tests parser with various type declarations

// Primitive types
I64 x;
U32 y;
F64 z;
I8 a;
U16 b;

// Pointer types
I64* ptr;
U8** double_ptr;
F64* float_ptr;

// Array types
I64[10] fixed_array;
U8[] dynamic_array;
I64[100] big_array;

// Named types (classes/unions)
CDate date;
TaskHandle handle;
MyStruct data;

// Complex types
I64*[5] array_of_pointers;
I64[10]* pointer_to_array;
CDate* date_ptr;
MyClass** class_double_ptr;

// Nested pointers
U8*** triple_ptr;
I64**** quad_ptr;
