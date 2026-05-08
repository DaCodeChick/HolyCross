// Test parameter handling

I64 Square(I64 x) {
    return x * x;
}

I64 Add(I64 a, I64 b) {
    return a + b;
}

U0 Main() {
    I64 result = Square(5);
    I64 sum = Add(3, 4);
}

Main;
