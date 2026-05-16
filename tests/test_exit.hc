extern I64 exit(I64 code);

I64 _start() {
    exit(42);
    return 0;
}
