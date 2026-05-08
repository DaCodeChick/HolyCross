// Test BSWAP instruction only

I64 TestBSwap()
{
    asm {
        MOV RAX, 256
        BSWAP RAX        // Reverse byte order
    }
    return 1;
}

I64 main()
{
    I64 a;
    a = TestBSwap();
    return a;
}
