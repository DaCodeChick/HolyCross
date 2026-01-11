// HolyC Variable Declaration Examples
// Tests parser with various variable declarations

// Simple declarations (no initializer)
I64 x;
U32 y;
F64 z;
I8 byte;
U16 word;

// Declarations with initializers
I64 count = 42;
U32 size = 1024;
F64 pi = 3.14159;
I8 flag = 1;

// Declarations with expressions
I64 sum = a + b;
U32 product = x * y;
F64 average = (a + b) / 2;

// Pointer declarations
I64* ptr = &x;
U8* buffer = &data;
F64* values = &array;

// Pointer with null
I64* null_ptr = 0;

// Array declarations (subscript after variable name)
I64 numbers[10];
U8 bytes[256];
F64 samples[100];

// Array with unsized
I64 dynamic[];
U8 buffer2[];

// Complex types
I64* ptr_array[5];              // Array of 5 I64 pointers
I64 (*array_ptr)[10];           // Pointer to array of 10 I64s

// Multiple similar declarations
I64 a;
I64 b;
I64 c;

// Declarations with various operators
I64 shifted = value << 2;
U32 masked = flags & 0xFF;
I64 negated = -original;
U8* incremented = ptr + 1;

// String and char initializers
U8* message = "Hello";
I64 ch = 'A';
