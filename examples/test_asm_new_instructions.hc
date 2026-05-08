// Test newly added x64 instructions: LEAVE, SETcc
// Note: MOVSX/MOVZX require more operand type support

I64 TestLeave()
{
    asm {
        PUSH RBP
        MOV RBP, RSP
        LEAVE       // Equivalent to: MOV RSP, RBP; POP RBP
    }
    return 1;
}

I64 TestSetCC()
{
    asm {
        // Test SETcc instructions
        MOV RAX, 5
        CMP RAX, 5
        SETE AL         // Should set AL to 1 (equal)
        
        MOV RBX, 10
        CMP RBX, 5
        SETG BL         // Should set BL to 1 (greater)
        
        MOV RCX, 3
        CMP RCX, 5
        SETL CL         // Should set CL to 1 (less)
    }
    return 2;
}

I64 Main()
{
    I64 a, b;
    a = TestLeave();
    b = TestSetCC();
    
    // Return sum: 1 + 2 = 3
    return a + b;
}

Main;
