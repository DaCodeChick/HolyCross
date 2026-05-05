// Test __DIR__ with #ifdef (it's always defined)

#ifdef __DIR__
U0 DirDefined() {
    // This should always be included
}
#endif

#ifndef __DIR__
U0 DirNotDefined() {
    // This should never be included
}
#endif

U0 Main() {
    DirDefined();
}
