extern I64 write(I64 fd, U8 *buf, I64 count);

U0 _start() {
    U8 *msg;
    msg = "test\n";
    write(1, msg, 5);
    
    // Exit with code 0
    I64 exit_code;
    exit_code = 0;
    asm {
        MOV RAX, 60
        MOV RDI, exit_code
        SYSCALL
    }
}
