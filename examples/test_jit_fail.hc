// This should fail - trying to call JIT-only function

#ifjit
U0 JitOnlyFunction() {
}
#endif

U0 Main() {
    JitOnlyFunction(); // Error: this function doesn't exist
}

Main;
