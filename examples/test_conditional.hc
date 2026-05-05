// Test conditional compilation with #ifdef/#ifndef

#define DEBUG
#define VERSION 2

#ifdef DEBUG
U0 DebugFunction() {
    // This should be included
}
#endif

#ifndef RELEASE
U0 NotReleaseFunction() {
    // This should be included (RELEASE is not defined)
}
#endif

#ifdef UNDEFINED_MACRO
U0 ShouldNotExist() {
    // This should NOT be included
}
#endif

U0 Main() {
    DebugFunction();
    NotReleaseFunction();
}
