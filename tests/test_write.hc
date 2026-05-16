extern I64 write(I64 fd, U8 *buf, I64 count);

// Simple test data in BSS
U8 msg[5];

I64 _start() {
    msg[0] = 'h';
    msg[1] = 'i';
    msg[2] = '\n';
    write(1, msg, 3);
    return 0;
}
