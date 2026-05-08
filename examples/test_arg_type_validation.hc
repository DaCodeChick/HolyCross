// Test function argument type validation

I64 ProcessNumber(I64 num)
{
    return num * 2;
}

U8* GetPointer()
{
    U8* ptr;
    return ptr;
}

I64 Main()
{
    // Valid call
    I64 x = ProcessNumber(42);
    
    // Type mismatch - passing pointer to integer function
    // HolyC is weakly typed and may allow this, but it should at least validate
    U8* ptr = GetPointer();
    I64 y = ProcessNumber(ptr);  // Potentially problematic
    
    return x + y;
}

Main;
