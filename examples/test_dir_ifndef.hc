// Test that #ifndef __DIR__ excludes code

#ifndef __DIR__
U0 ShouldNotExist() {
}
#endif

#ifdef __DIR__
U0 Main() {
}
#endif

Main;
