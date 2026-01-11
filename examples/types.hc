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

// Array types (subscript comes after variable name, like C)
I64 fixed_array[10];
U8 dynamic_array[];
I64 big_array[100];

// Named types (classes/unions)
CDate date;
TaskHandle handle;
MyStruct data;

// Complex types
I64* array_of_pointers[5];      // Array of 5 I64 pointers
I64 (*pointer_to_array)[10];    // Pointer to array of 10 I64s
CDate* date_ptr;
MyClass** class_double_ptr;

// Nested pointers
U8*** triple_ptr;
I64**** quad_ptr;
