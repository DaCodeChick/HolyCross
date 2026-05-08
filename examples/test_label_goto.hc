// Test label and goto support

U0 TestLabels() {
    I64 x = 0;
    
    // Jump forward to skip increment
    goto skip;
    
    x = x + 1;  // This should be skipped
    
skip:
    x = x + 10;
    
    // Jump backward
    if (x < 100) {
        goto skip;
    }
}

U0 Main() {
    TestLabels;
}

Main;
