// Test nested #ifdef / #ifndef conditional compilation
// No macros defined - all branches should be the "not defined" paths

U0 Main() {
    "Testing nested conditional compilation...\n";
    
    #ifdef DEBUG
    "DEBUG is defined\n";
        #ifdef VERBOSE
        "  VERBOSE is also defined (nested)\n";
        #endif
        #ifndef RELEASE
        "  RELEASE is not defined (nested)\n";
        #endif
    #endif
    
    #ifndef RELEASE
    "RELEASE is not defined\n";
        #ifdef DEBUG
        "  But DEBUG is defined (nested)\n";
        #else
        "  And DEBUG is also not defined (nested)\n";
        #endif
    #endif
    
    "Nested conditionals work!\n";
}
