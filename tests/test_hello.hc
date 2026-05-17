extern I64 puts(U8 *s);
extern U0 exit(I64 status);

U0 main() {
    U8 *msg;
    msg = "Hello from HolyC!";
    puts(msg);
}

U0 _start() {
    main();
    exit(0);
}
