// Test #ifdef / #ifndef / #else conditional compilation
// No macros defined - test the else branches

U0 Main() {
    "Testing conditional compilation with #else...\n";
    
    #ifdef DEBUG
    "DEBUG is defined - in the ifdef branch\n";
    #else
    "DEBUG is not defined - in the else branch\n";
    #endif
    
    #ifdef RELEASE
    "RELEASE is defined - in the ifdef branch\n";
    #else
    "RELEASE is not defined - in the else branch\n";
    #endif
    
    #ifndef DEBUG
    "DEBUG is not defined - in the ifndef branch\n";
    #else
    "DEBUG is defined - in the else branch\n";
    #endif
    
    #ifndef RELEASE
    "RELEASE is not defined - in the ifndef branch\n";
    #else
    "RELEASE is defined - in the else branch\n";
    #endif
    
    "All conditional branches tested!\n";
}
