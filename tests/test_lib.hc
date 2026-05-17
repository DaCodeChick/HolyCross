// Test shared library with exported functions
extern I64 printf(U8 *fmt);

U0 HelloFromLib() {
    printf("Hello from shared library!\n");
}

I64 Add(I64 a, I64 b) {
    return a + b;
}

I64 Multiply(I64 a, I64 b) {
    return a * b;
}
