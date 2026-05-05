// Verify JIT code is excluded

#ifjit
U0 ShouldNotExist() {
}
#endif

#ifaot
U0 ShouldExist() {
}
#endif

U0 Main() {
    ShouldExist();
    // If we tried to call ShouldNotExist(), compilation would fail
}
