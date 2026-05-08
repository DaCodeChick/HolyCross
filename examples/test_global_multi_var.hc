// Test global multi-variable declarations

I64 g1, g2, g3;

I64 Main()
{
    g1 = 10;
    g2 = 20;
    g3 = 30;
    return g1 + g2 + g3;  // Should return 60
}

Main;
