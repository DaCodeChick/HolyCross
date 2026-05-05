// Test x64 assembly parsing and encoding
// This demonstrates the inline assembly support

asm {
    // Simple function that returns 42
    _GetFortyTwo::
        PUSH RBP
        MOV RBP, RSP
        MOV RAX, 42
        POP RBP
        RET
}

// This won't actually call it yet (codegen integration pending)
// But the assembly is now parsed and can be encoded
