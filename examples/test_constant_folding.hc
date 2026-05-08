// Test constant folding optimization
I64 Main()
{
    // These should be folded at compile time
    I64 a = 2 + 3;           // Should fold to 5
    I64 b = 10 * 4;          // Should fold to 40
    I64 c = 100 - 25;        // Should fold to 75
    I64 d = 20 / 4;          // Should fold to 5
    I64 e = 17 % 5;          // Should fold to 2
    
    // Bitwise operations
    I64 f = 0xFF & 0x0F;     // Should fold to 15
    I64 g = 0x10 | 0x01;     // Should fold to 17
    I64 h = 0xFF ^ 0xAA;     // Should fold to 85
    I64 i = 2 << 3;          // Should fold to 16
    I64 j = 32 >> 2;         // Should fold to 8
    
    // Comparisons
    I64 k = 5 > 3;           // Should fold to 1 (true)
    I64 l = 10 < 5;          // Should fold to 0 (false)
    I64 m = 7 == 7;          // Should fold to 1 (true)
    
    // Unary operations
    I64 n = -42;             // Should fold to -42
    I64 o = ~0;              // Should fold to -1
    
    // Complex expressions (nested folding)
    I64 p = (2 + 3) * 4;     // Should fold to 20
    I64 q = 100 - (10 * 2);  // Should fold to 80
    
    return a + b + c + d + e;
}

Main;
