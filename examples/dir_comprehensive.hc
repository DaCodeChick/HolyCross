// Comprehensive __DIR__ demonstration
// The __DIR__ builtin symbol is always defined by the preprocessor
// It represents the source file's parent directory

// Test 1: __DIR__ is defined
#ifdef __DIR__
U0 TestDirDefined() {
    // This code is included because __DIR__ is always defined
}
#endif

// Test 2: __DIR__ is NOT undefined
#ifndef __DIR__
U0 ThisShouldNotExist() {
    // This code is excluded because __DIR__ IS defined
}
#endif

// Test 3: Use with #else
#ifdef __DIR__
U0 InIfdefBranch() {
}
#else
U0 InElseBranch() {
    // This would not be included
}
#endif

// Test 4: Combined with other symbols
#ifdef TRUE
#ifdef __DIR__
U0 BothDefined() {
    // Both TRUE and __DIR__ are defined
}
#endif
#endif

U0 Main() {
    TestDirDefined();
    InIfdefBranch();
    BothDefined();
}
