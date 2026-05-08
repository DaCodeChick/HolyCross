// Test subscript index validation with pointer

I64 ProcessArray(I64* arr, F64 idx)
{
    // This should trigger an error - float used as array index
    return arr[idx];
}

I64 Main()
{
    I64 nums[5];
    return 42;
}

Main;
