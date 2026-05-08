// Test subscript validation without arrays (use function params)

I64 GetElement(I64* ptr, F64 bad_idx)
{
    // This should error - float as index
    return ptr[bad_idx];
}

I64 Main()
{
    return 42;
}

Main;
