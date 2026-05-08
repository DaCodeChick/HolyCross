// Test #include with conditional compilation

#include "platform"

U0 Main() {
    "Testing include with conditionals\n";
    
    #ifndef PLATFORM_DEFINED
    "Platform not defined - using defaults\n";
    #else
    "Platform is defined\n";
    #endif
    
    "Test complete!\n";
}

Main;
