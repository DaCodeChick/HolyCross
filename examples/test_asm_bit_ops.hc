// Test bit manipulation instructions

I64 TestBitScan()
{
    asm {
        MOV RAX, 16      // Small immediate
        BSF RBX, RAX     // Find first set bit
        BSR RCX, RAX     // Find last set bit
    }
    return 1;
}

I64 TestBSwap()
{
    asm {
        MOV RAX, 256
        BSWAP RAX        // Reverse byte order
    }
    return 2;
}

I64 main()
{
    I64 a, b;
    a = TestBitScan();
    b = TestBSwap();
    
    // Return sum: 1 + 2 = 3
    return a + b;
}
