// Test inline assembly

U0 TestAsm() {
    asm {
        MOV RAX, 42
        PUSH RAX
        POP RBX
    }
}

U0 Main() {
    TestAsm();
}

Main;
