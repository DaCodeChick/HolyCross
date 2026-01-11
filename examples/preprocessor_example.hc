// HolyCross Compiler - Preprocessor #define Example

#define NULL 0
#define TRUE 1
#define FALSE 0
#define MAX_SIZE 100

U0 TestDefines() {
    I64 value;
    value = NULL;
    
    if (TRUE) {
        "TRUE is defined correctly\n";
    }
    
    if (FALSE) {
        "This should not print\n";
    } else {
        "FALSE is defined correctly\n";
    }
    
    I64 size;
    size = MAX_SIZE;
}

U0 Main() {
    "Testing preprocessor defines...\n";
    TestDefines;
}
