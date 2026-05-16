// Test direct syscall
U0 _start() {
    // write(1, "Hello!\n", 7)
    I64 fd;
    U8 *msg;
    I64 len;
    
    fd = 1;
    msg = "Hello!\n";
    len = 7;
    
    asm {
        MOV RAX, 1      // write syscall
        MOV RDI, fd
        MOV RSI, msg
        MOV RDX, len
        SYSCALL
    }
}
