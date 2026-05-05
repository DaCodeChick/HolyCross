// Comprehensive inline assembly test

I64 TestMultipleInstructions()
{
    asm {
        NOP
        PUSH RAX
        POP RAX
        MOV RBX, 100
    }
    return 1;
}

I64 TestWithWhitespace()
{
    asm {
        
        MOV   RAX,   42
        
        NOP
        
    }
    return 2;
}

I64 main()
{
    I64 a;
    I64 b;
    a = TestMultipleInstructions();
    b = TestWithWhitespace();
    return a + b;  // Should return 3
}
