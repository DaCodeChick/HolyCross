// Test __DIR__ in a subdirectory

#ifdef __DIR__
U0 TestFromSubdir() {
}
#endif

U0 Main() {
    TestFromSubdir();
}

Main;
