// Test Bool type with TRUE, FALSE, and NULL constants

// Declare the constants (these would normally be in a standard library)
I64 TRUE = 1;
I64 FALSE = 0;
I64 NULL = 0;

Bool IsPositive(I64 x) {
    if (x > 0)
        return TRUE;
    else
        return FALSE;
}

U0 TestBool() {
    Bool flag;
    Bool result;
    
    flag = TRUE;
    if (flag) {
        "flag is TRUE\n";
    }
    
    flag = FALSE;
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
    
    ptr = NULL;
    if (ptr == NULL) {
        "Pointer is NULL\n";
    }
}

U0 Main() {
    "Testing Bool type with TRUE/FALSE/NULL\n\n";
    
    TestBool;
    "\n";
    TestNull;
    
    "\nAll tests passed!\n";
}

Main;
