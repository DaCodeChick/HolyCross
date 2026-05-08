// Test BSF instruction only

I64 TestBSF()
{
    asm {
        MOV RAX, 16
        BSF RBX, RAX
    }
    return 1;
}

I64 main()
{
    return TestBSF();
}
