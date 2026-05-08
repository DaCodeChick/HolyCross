// Test inline assembly integration

I64 GetFortyTwo()
{
    I64 result;
    
    asm {
        MOV RAX, 42
    }
    
    return 42;  // The inline assembly doesn't actually affect the return yet
}

I64 Main()
{
    I64 x;
    x = GetFortyTwo();
    return x;
}

Main;
