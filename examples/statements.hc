// HolyC Control Flow Statements Examples
// Demonstrates all statement types supported by the parser

// ============================================================================
// BLOCK STATEMENTS
// ============================================================================

U0 TestBlocks() {
    // Simple block
    {
        I64 x = 1;
        I64 y = 2;
        I64 z = x + y;
    }
    
    // Nested blocks
    {
        I64 outer = 100;
        {
            I64 inner = 200;
            outer = outer + inner;
        }
    }
}

// ============================================================================
// IF STATEMENTS
// ============================================================================

U0 TestIf() {
    I64 x;
    I64 y;
    I64 z;
    
    // Simple if
    if (x > 0)
        y = 1;
    
    // If with block
    if (x > 0) {
        y = 1;
        z = 2;
    }
    
    // If-else
    if (x > 0)
        y = 1;
    else
        y = 0;
    
    // If-else with blocks
    if (x > 0) {
        y = 1;
        z = 2;
    } else {
        y = 0;
        z = 0;
    }
    
    // If-else chain
    if (x > 10)
        y = 3;
    else if (x > 5)
        y = 2;
    else if (x > 0)
        y = 1;
    else
        y = 0;
    
    // Nested if statements
    if (x > 0) {
        if (y > 0) {
            z = x + y;
        } else {
            z = x - y;
        }
    }
}

// ============================================================================
// WHILE LOOPS
// ============================================================================

U0 TestWhile() {
    I64 x;
    I64 y;
    I64 z;
    
    // Simple while
    while (x < 10)
        x++;
    
    // While with block
    while (x < 10) {
        y = y + x;
        x++;
    }
    
    // Nested while
    while (x < 10) {
        while (y < 5) {
            z = z + 1;
            y++;
        }
        x++;
    }
}

// ============================================================================
// DO-WHILE LOOPS
// ============================================================================

U0 TestDoWhile() {
    I64 x;
    I64 y;
    I64 z;
    
    // Simple do-while
    do
        x++;
    while (x < 10);
    
    // Do-while with block
    do {
        y = y + x;
        x++;
    } while (x < 10);
    
    // Nested do-while
    do {
        do {
            z++;
        } while (z < 5);
        x++;
    } while (x < 10);
}

// ============================================================================
// FOR LOOPS
// ============================================================================

U0 TestFor() {
    I64 sum;
    I64 product;
    I64 n;
    I64 result;
    I64 done;
    
    // Simple for loop
    for (I64 i = 0; i < 10; i++)
        sum = sum + i;
    
    // For loop with block
    for (I64 i = 0; i < 10; i++) {
        sum = sum + i;
        product = product * i;
    }
    
    // For loop with complex expressions
    for (I64 i = 0; i < n * 2; i = i + 2) {
        result = result + i;
    }
    
    // For loop with empty parts (infinite loop-like syntax)
    for (;;) {
        if (done)
            break;
    }
}

// ============================================================================
// RETURN STATEMENTS  
// ============================================================================

I64 TestReturn() {
    I64 x;
    I64 y;
    I64 z;
    
    // Return with value
    return x + y * z;
}

// ============================================================================
// BREAK STATEMENTS
// ============================================================================

U0 TestBreak() {
    I64 x;
    I64 target;
    
    // Break in while loop
    while (x < 100) {
        if (x == 50)
            break;
        x++;
    }
    
    // Break in for loop
    for (I64 i = 0; i < 100; i++) {
        if (i == target)
            break;
    }
    
    // Break in nested loop (breaks inner loop only)
    for (I64 i = 0; i < 10; i++) {
        for (I64 j = 0; j < 10; j++) {
            if (j == 5)
                break;
        }
    }
}

// ============================================================================
// COMPLEX COMBINATIONS
// ============================================================================

U0 TestComplex() {
    I64 n;
    I64 i;
    I64 j;
    I64 m;
    I64 x;
    I64 y;
    I64 temp;
    I64 result;
    
    // Complex nested control flow
    for (i = 0; i < n; i++) {
        if (i != 0) {
            while (j < m) {
                j++;
            }
        }
    }
    
    // Expression statements mixed with control flow
    x = 10;
    y = 20;
    
    if (x < y) {
        temp = x;
        x = y;
        y = temp;
    }
    
    result = x + y;
}

U0 Main() {
    TestBlocks();
    TestIf();
    TestWhile();
    TestDoWhile();
    TestFor();
    TestBreak();
    TestComplex();
}
