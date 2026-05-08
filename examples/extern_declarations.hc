// Extern Declaration Example
// HolyC supports extern forward declarations for functions and types.
// This allows splitting code across multiple files.

// Forward declaration: tells compiler the function exists elsewhere
extern U0 LibraryFunction();

// Multiple extern declarations are allowed (redundant but valid)
extern U0 HelperFunction();
extern U0 HelperFunction();  // OK - duplicate extern

// Define the actual function after declaring it extern
U0 HelperFunction() {
    I64 initialized = 1;
}

// Regular function without extern
U0 LocalFunction() {
    I64 local = 42;
}

U0 Main() {
    HelperFunction;
    LocalFunction;
}

Main;
