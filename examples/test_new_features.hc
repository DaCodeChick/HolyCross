// Test new codegen features: switch, goto, globals, increment/decrement

I64 global_counter = 0;
I64 global_sum = 100;

U0 TestSwitch(I64 value) {
    switch (value) {
        case 1:
            "Case 1\n";
            break;
        case 2:
            "Case 2\n";
            break;
        case 3:
            "Case 3\n";
            break;
        default:
            "Default case\n";
            break;
    }
}

U0 TestGoto() {
    I64 x = 0;
    
start:
    x = x + 1;
    
    if (x < 5)
        goto start;
    
    "Goto loop done\n";
}

U0 TestIncrementDecrement() {
    I64 x = 10;
    
    x++;  // post-increment
    ++x;  // pre-increment
    x--;  // post-decrement
    --x;  // pre-decrement
    
    "Increment/decrement test done\n";
}

U0 TestGlobals() {
    global_counter = global_counter + 1;
    global_sum = global_sum + 50;
    "Global variables updated\n";
}

U0 Main() {
    "Testing new features...\n";
    
    "\n=== Switch Statement Test ===\n";
    TestSwitch(1);
    TestSwitch(2);
    TestSwitch(99);
    
    "\n=== Goto Test ===\n";
    TestGoto();
    
    "\n=== Increment/Decrement Test ===\n";
    TestIncrementDecrement();
    
    "\n=== Global Variables Test ===\n";
    TestGlobals();
    
    "\nAll tests completed!\n";
}
