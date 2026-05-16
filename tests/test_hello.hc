extern I64 puts(U8 *s);

U0 main() {
    U8 *msg;
    msg = "Hello from HolyC!";
    puts(msg);
}

U0 _start() {
    main();
}
