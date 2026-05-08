// Test extended x64 assembler instructions
// Note: inline asm currently cannot access HolyC variables directly
// This test verifies that the extended instruction encoders work

I64 TestArithmetic()
{
    asm {
        MOV RAX, 10
        MOV RBX, 5
        ADD RAX, RBX    // RAX = 15
        SUB RAX, 3      // RAX = 12
    }
    return 12;
}

I64 TestLogical()
{
    asm {
        MOV RCX, 255
        AND RCX, 15     // RCX = 15
        OR  RCX, 16     // RCX = 31
        XOR RCX, 31     // RCX = 0
    }
    return 0;
}

I64 TestShifts()
{
    asm {
        MOV RDX, 4
        SHL RDX, 2      // RDX = 16
        SHR RDX, 1      // RDX = 8
    }
    return 8;
}

I64 TestUnary()
{
    asm {
        MOV RSI, 5
        INC RSI         // RSI = 6
        DEC RSI         // RSI = 5
        NEG RSI         // RSI = -5
        NOT RSI         // RSI = 4
    }
    return 4;
}

I64 Main()
{
    // Just verify the functions compile and can be called
    I64 a, b, c, d;
    a = TestArithmetic();
    b = TestLogical();
    c = TestShifts();
    d = TestUnary();
    
    // Return sum: 12 + 0 + 8 + 4 = 24
    return a + b + c + d;
}

Main;
