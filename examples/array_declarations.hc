// Array Declaration Example  
// HolyC uses C-style array syntax: Type name[size];

// Global arrays
I64 global_numbers[10];
U8 global_buffer[256];

// Class with array members
class CDataBuffer {
    U8 data[512];      // Fixed-size buffer
    I64 counters[5];   // Array of counters
};

// Function with array parameter
U0 ProcessBuffer(U8 buffer[256], I64 size) {
    // Local array declaration
    I64 local_array[20];
    local_array[0] = size;
}

U0 Main() {
    // Local arrays
    I64 numbers[10];
    U8 text[100];
    
    // Array initialization and access
    numbers[0] = 42;
    numbers[1] = 100;
}

Main;
