// Test combined control flow - Fibonacci
I64 Fib(I64 n) {
    if (n <= 1) {
        return n;
    }
    
    I64 a = 0;
    I64 b = 1;
    I64 i = 2;
    
    while (i <= n) {
        I64 temp = a + b;
        a = b;
        b = temp;
        i = i + 1;
    }
    
    return b;
}

U0 Main() {
    I64 f10 = Fib(10);  // Should return 55
    "Combined control flow test completed\n";
}
