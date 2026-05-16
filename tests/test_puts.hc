extern I64 puts(U8 *s);

U0 _start() {
    U8 *msg;
    msg = "test";
    puts(msg);
}
