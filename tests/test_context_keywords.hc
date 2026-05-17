// Test context-sensitive keywords as parameter names
extern I64 puts(U8 *s);
extern U0 exit(I64 status);

U0 test_params(I64 reserved, I64 pad) {
    // Both 'reserved' and 'pad' should work as parameter names
    I64 result;
    result = reserved + pad;
}

U0 test_vars() {
    // Both should also work as variable names
    I64 reserved;
    I64 pad;
    reserved = 10;
    pad = 20;
}

U0 _start() {
    test_params(1, 2);
    test_vars();
    puts("Context-sensitive keywords work!");
    exit(0);
}
