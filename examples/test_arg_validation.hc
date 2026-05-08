// Test function argument count validation

I64 Add(I64 a, I64 b)
{
    return 42;  // Simplified body
}

I64 Main()
{
    // Valid call - should work fine
    I64 x = Add(5, 10);
    
    // Invalid calls - should produce type errors
    I64 z = Add(5);           // Error: expects 2 args, got 1
    I64 w = Add(5, 10, 15);   // Error: expects 2 args, got 3
    
    return x;
}

Main;
