// Simple test of extended x64 instructions

I64 Main()
{
    I64 result;
    
    // Test that instructions parse and encode
    asm {
        NOP
        MOV RAX, 10
        ADD RAX, 5
        SUB RAX, 3
        AND RAX, 255
        OR RAX, 0
        XOR RAX, 0
        INC RAX
        DEC RAX
    }
    
    // Return a known value
    result = 42;
    return result;
}

Main;
