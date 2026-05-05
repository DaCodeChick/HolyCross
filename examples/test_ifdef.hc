// Test #ifdef / #ifndef conditional compilation
// These should all be undefined by default

U0 Main() {
    "Starting conditional compilation test...\n";
    
    #ifdef DEBUG
    "DEBUG is defined - this should NOT print\n";
    #endif
    
    #ifdef RELEASE
    "RELEASE is defined - this should NOT print\n";
    #endif
    
    #ifndef RELEASE
    "RELEASE is not defined - this should print\n";
    #endif
    
    #ifndef DEBUG
    "DEBUG is not defined - this should print\n";
    #endif
    
    "Test complete!\n";
}
