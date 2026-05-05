// Test #ifaot and #ifjit directives

#ifaot
U0 AotFunction() {
    // This should be included (we're compiling AOT)
}
#endif

#ifjit
U0 JitFunction() {
    // This should NOT be included (no JIT support yet)
}
#endif

// Test with #else
#ifaot
U0 InAotBranch() {
}
#else
U0 NotInAotBranch() {
}
#endif

#ifjit
U0 InJitBranch() {
}
#else
U0 NotInJitBranch() {
    // This should be included (JIT is false, so else is taken)
}
#endif

U0 Main() {
    AotFunction();
    InAotBranch();
    NotInJitBranch();
}
