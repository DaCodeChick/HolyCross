// Test global multi-variable declarations with arrays

I64 arr1[3], scalar, arr2[2];

I64 main()
{
    arr1[0] = 1;
    arr1[1] = 2;
    arr1[2] = 3;
    
    scalar = 10;
    
    arr2[0] = 4;
    arr2[1] = 5;
    
    return arr1[0] + arr1[1] + arr1[2] + scalar + arr2[0] + arr2[1];  // 1+2+3+10+4+5 = 25
}
