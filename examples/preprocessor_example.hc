// Example demonstrating HolyC preprocessor directives
// Note: HolyC preprocessor is simpler than C/C++
// Function-like macros may not be supported - using simple defines only

#define PI 3.14159
#define MAX_SIZE 1024

// Platform-specific compilation
#ifaot
    // Code for ahead-of-time compilation
    #define COMPILE_MODE "AOT Mode"
#endif

#ifjit
    // Code for just-in-time compilation
    #define COMPILE_MODE "JIT Mode"
#endif

// Type definitions using preprocessor (standard library pattern)
#define Bool U8
#define TRUE 1
#define FALSE 0
#define NULL 0

// Conditional compilation
#ifdef DEBUG
    #define DEBUG_MSG "Debug build enabled"
#else
    #define DEBUG_MSG "Release build"
#endif

// Compile-time execution - unique HolyC feature
#exe {
    // This code runs during compilation
    Print("Compiling at: %s\n", Now);
}

U0 CalculateArea(F64 radius) {
    F64 area = PI * radius * radius;
    Print("Area of circle: %f\n", area);
}

U0 Main() {
    #ifdef DEBUG
        Print("DEBUG: Starting program\n");
    #endif
    
    CalculateArea(5.0);
    
    Bool flag = TRUE;
    U8 *ptr = NULL;
    
    #ifndef MAX_SIZE
        #assert FALSE  // This won't fire since MAX_SIZE is defined
    #endif
    
    U64 buffer[MAX_SIZE];
    
    #ifdef COMPILE_MODE
        Print("Compilation mode: %s\n", COMPILE_MODE);
    #endif
    
    Print("Build type: %s\n", DEBUG_MSG);
    
    #ifdef DEBUG
        Print("DEBUG: Program complete\n");
    #endif
}
