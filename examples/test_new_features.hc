// Test new codegen features: switch, globals, increment/decrement

I64 global_counter = 0;
I64 global_sum = 100;

U0 TestSwitch(I64 value) {
    I64 result = 0;
    
    switch (value) {
        case 1:
            result = 1;
            break;
        case 2:
            result = 2;
            break;
        case 3:
            result = 3;
            break;
        default:
            result = 99;
            break;
    }
}

// Goto not yet supported
/*
U0 TestGoto() {
    I64 x = 0;
    
start:
    x = x + 1;
    
    if (x < 5)
        goto start;
}
*/

U0 TestIncrementDecrement() {
    I64 x = 10;
    
    x++;  // post-increment
    x++;  // pre-increment (parser treats ++x as post-increment for now)
    x--;  // post-decrement
    x--;  // pre-decrement (parser treats --x as post-decrement for now)
}

U0 TestGlobals() {
    global_counter = global_counter + 1;
    global_sum = global_sum + 50;
}

U0 Main() {
    TestSwitch(1);
    TestSwitch(2);
    TestSwitch(99);
    
    TestIncrementDecrement();
    TestGlobals();
}

Main;
