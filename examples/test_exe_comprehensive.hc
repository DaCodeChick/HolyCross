// Test #exe with various features

#define VERSION 100

#exe {
    Print("Compile-time execution:\n");
    
    I64 factorial = 1;
    I64 i = 1;
    while (i <= 5) {
        factorial = factorial * i;
        i = i + 1;
    }
    Print("5! = %d\n", factorial);
    
    if (factorial > 100) {
        Print("Factorial is large!\n");
    }
}

U0 Main() {
    // Runtime code would go here
}
