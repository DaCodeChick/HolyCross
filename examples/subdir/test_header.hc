// Header file to test __DIR__

#ifdef __DIR__
U0 HeaderFunction() {
}
#endif

#ifndef __DIR__
U0 DirNotDefinedInHeader() {
}
#endif
