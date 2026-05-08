// Comprehensive label and goto test

U0 TestForwardJump() {
    I64 x = 0;
    goto forward;
    x = 100;  // Should be skipped
forward:
    x = 42;
}

U0 TestBackwardJump() {
    I64 counter = 0;
loop_start:
    counter = counter + 1;
    if (counter < 5) {
        goto loop_start;
    }
}

U0 TestMultipleLabels() {
    I64 state = 1;
    
    if (state == 1) {
        goto label_a;
    }
    if (state == 2) {
        goto label_b;
    }
    
label_a:
    state = 10;
    goto finish;
    
label_b:
    state = 20;
    
finish:
    state = 0;
}

U0 Main() {
    TestForwardJump;
    TestBackwardJump;
    TestMultipleLabels;
}

Main;
