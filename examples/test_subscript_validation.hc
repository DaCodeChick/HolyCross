// Test array subscript index validation

I64 Main()
{
    I64 arr[5];
    F64 flt;
    
    // Valid subscript - integer literal
    I64 x = arr[0];
    
    // Invalid subscript - float
    I64 bad = arr[flt];  // Error: float as index
    
    return x;
}

Main;
