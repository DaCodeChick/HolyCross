// Simple test with wrong argument count

I64 Add(I64 a, I64 b)
{
    return 42;
}

I64 Main()
{
    I64 x = Add(5);  // Wrong: expects 2 args, got 1
    return x;
}

Main;
