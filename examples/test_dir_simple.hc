// Simpler test for __DIR__

#ifdef __DIR__
U0 Main() {
}
#endif

#ifndef __DIR__
U0 Main() {
    // This should not be here
}
#endif

Main;
