extern I64 puts(U8 *s);

U0 _start() {
    U8 *msg;
    msg = "test";
    puts(msg);
    
    // Exit with code 0
    I64 exit_code;
    exit_code = 0;
    asm {
        MOV RAX, 60
        MOV RDI, exit_code
        SYSCALL
    }
}
