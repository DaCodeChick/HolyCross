// HolyC Expression Examples
// Tests parser with various expression types

U0 TestArithmetic() {
    I64 a;
    I64 b;
    I64 c;
    
    // Simple arithmetic
    a = 1 + 2;
    a = 3 * 4;
    a = 5 - 6;
    a = 7 / 8;
    a = 9 % 10;
    
    // Precedence
    a = 1 + 2 * 3;
    a = (1 + 2) * 3;
    a = 2 * 3 + 4;
}

U0 TestUnary() {
    I64 a;
    I64 flag;
    I64 mask;
    
    // Unary operators
    a = -42;
    a = +100;
    a = !flag;
    a = ~mask;
}

U0 TestComplex() {
    I64 a;
    I64 b;
    I64 c;
    I64 x;
    I64 y;
    I64 z;
    I64 w;
    
    // Complex expressions
    a = -a + b * c;
    a = (x + y) * (z - w);
    a = a * b + c * c;
}

U0 Main() {
    TestArithmetic();
    TestUnary();
    TestComplex();
}

/*
ADDITIONAL EXPRESSION EXAMPLES (not yet fully supported):

// Power operator (HolyC-specific)
2`8
3`2`2

// Logical XOR (HolyC-specific)
a ^^ b
x ^^ y ^^ z
