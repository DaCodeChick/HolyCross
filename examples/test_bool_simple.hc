// Test Bool type

Bool IsPositive(I64 x) {
    if (x > 0)
        return 1; // TRUE
    else
        return 0; // FALSE
}

U0 TestBool() {
    Bool flag;
    Bool result;
    
    flag = 1; // TRUE
    if (flag) {
        "flag is TRUE\n";
    }
    
    flag = 0; // FALSE
    if (!flag) {
        "flag is FALSE\n";
    }
    
    result = IsPositive(42);
    if (result) {
        "42 is positive\n";
    }
    
    result = IsPositive(-5);
    if (!result) {
        "-5 is not positive\n";
    }
}

U0 TestNull() {
    I64 *ptr;
    
    ptr = 0; // NULL
    if (ptr == 0) {
        "Pointer is NULL\n";
    }
}

U0 Main() {
    "Testing Bool type\n\n";
    
    TestBool;
    "\n";
    TestNull;
    
    "\nAll tests passed!\n";
}
