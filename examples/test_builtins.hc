// Test builtin preprocessor symbols

U0 Main() {
    "Testing builtin preprocessor symbols...\n";
    
    #ifdef TRUE
    "TRUE is defined (builtin)\n";
    #endif
    
    #ifdef FALSE
    "FALSE is defined (builtin)\n";
    #endif
    
    #ifdef NULL
    "NULL is defined (builtin)\n";
    #endif
    
    #ifndef UNDEFINED
    "UNDEFINED is not defined (correct)\n";
    #endif
    
    "All builtins work!\n";
}

Main;
