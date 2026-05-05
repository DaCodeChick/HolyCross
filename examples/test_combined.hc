// Test #include and #ifdef together

#include "level1"

U0 Main() {
    "Combined test: include + conditionals\n";
    
    #ifndef UNDEFINED_MACRO
    "This should print (macro not defined)\n";
    #endif
    
    #ifdef UNDEFINED_MACRO
    "This should NOT print\n";
    #else
    "This should print (else branch)\n";
    #endif
    
    "Test complete!\n";
}
