// Test __DIR__ preprocessor symbol

#ifdef __DIR__
U0 DirIsDefined() {
    // __DIR__ is defined as a builtin symbol
}
#endif

#ifndef __DIR__
U0 DirNotDefined() {
    // This should not be compiled
}
#endif

U0 Main() {
    DirIsDefined();
}

Main;
