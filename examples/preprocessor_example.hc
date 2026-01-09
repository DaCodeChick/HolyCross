// Example demonstrating HolyC preprocessor directives

#define PI 3.14159
#define MAX_SIZE 1024
#define MIN(a, b) ((a) < (b) ? (a) : (b))

// Conditional compilation
#ifdef DEBUG
    #define LOG(msg) Print("DEBUG: %s\n", msg)
#else
    #define LOG(msg) // No-op in release mode
#endif

// Platform-specific compilation
#ifaot
    // Code for ahead-of-time compilation
    #define COMPILE_MODE "AOT"
#endif

#ifjit
    // Code for just-in-time compilation
    #define COMPILE_MODE "JIT"
#endif

// Type definitions using preprocessor
#define Bool U8
#define TRUE 1
#define FALSE 0
#define NULL 0

// Compile-time execution
#exe {
    // This code runs at compile time
    Print("Compiling at: %s\n", Now);
}

U0 CalculateArea(F64 radius) {
    F64 area = PI * radius * radius;
    Print("Area of circle: %f\n", area);
}

U0 Main() {
    #ifdef DEBUG
        LOG("Starting program");
    #endif
    
    CalculateArea(5.0);
    
    Bool flag = TRUE;
    U8 *ptr = NULL;
    
    #ifndef MAX_SIZE
        #assert FALSE  // This won't fire since MAX_SIZE is defined
    #endif
    
    U64 buffer[MAX_SIZE];
    
    Print("Compilation mode: %s\n", COMPILE_MODE);
    
    #ifdef DEBUG
        LOG("Program complete");
    #endif
}
