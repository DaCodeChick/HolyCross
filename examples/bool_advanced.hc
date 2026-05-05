// Bool type tests without preprocessor macros

// Test Bool variable declarations
Bool TestBoolVariables() {
    Bool flag1;
    Bool flag2 = 1;
    Bool flag3 = 0;
    
    flag1 = 1;
    
    return flag1;
}

// Test Bool parameters and return
Bool AndOp(Bool a, Bool b) {
    if (a) {
        if (b) {
            return 1;
        }
    }
    return 0;
}

Bool OrOp(Bool a, Bool b) {
    if (a) {
        return 1;
    }
    if (b) {
        return 1;
    }
    return 0;
}

Bool NotOp(Bool a) {
    if (a) {
        return 0;
    }
    return 1;
}

// Test Bool in conditionals
I64 ConditionalTest() {
    Bool condition = 1;
    
    if (condition) {
        return 42;
    }
    
    return 0;
}

// Test Bool comparisons
Bool ComparisonTest(I64 x, I64 y) {
    if (x == y) {
        return 1;
    }
    return 0;
}

// Main test function
U0 Main() {
    Bool result1 = TestBoolVariables();
    Bool result2 = AndOp(1, 0);
    Bool result3 = OrOp(1, 0);
    Bool result4 = NotOp(0);
    
    I64 condResult = ConditionalTest();
    Bool cmpResult = ComparisonTest(42, 42);
}
