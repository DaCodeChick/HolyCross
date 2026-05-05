// Test #exe for compile-time execution
// Currently just parses; execution will be implemented later

#define MAX_SIZE 256

#exe Print("Compile time message\n");

U0 TestMacro() {
    I64 size = MAX_SIZE;
}

U0 Main() {
    TestMacro();
}
