// Comprehensive test: __DIR__ expansion + other macros

#define TRUE 1
#define FALSE 0
#define NULL 0

#define MAX_PATH 256
#define CURRENT_DIR __DIR__

U0 TestMacroExpansion() {
    // All these macros should expand properly
    I64 true_val = TRUE;
    I64 false_val = FALSE;
    I64 null_val = NULL;
    I64 max = MAX_PATH;
}

// Test that TRUE, FALSE, NULL work in conditionals
#ifdef TRUE
U0 TrueIsDefined() {
}
#endif

#ifdef FALSE
U0 FalseIsDefined() {
}
#endif

#ifdef NULL
U0 NullIsDefined() {
}
#endif

#ifdef __DIR__
U0 DirIsDefined() {
}
#endif

U0 Main() {
    TestMacroExpansion();
    TrueIsDefined();
    FalseIsDefined();
    NullIsDefined();
    DirIsDefined();
}

Main;
