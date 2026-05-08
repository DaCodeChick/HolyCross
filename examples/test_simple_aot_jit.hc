// Simple test for #ifaot and #ifjit

#define DEBUG

#ifaot
U0 AotFunction() {
}
#endif

#ifjit
U0 JitFunction() {
}
#endif

#ifaot
#ifdef DEBUG
U0 AotDebugFunction() {
}
#endif
#endif

U0 Main() {
    AotFunction();
    AotDebugFunction();
}

Main;
