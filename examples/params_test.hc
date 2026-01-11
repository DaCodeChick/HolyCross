// Test function parameters
I64 Add(I64 a, I64 b) {
    return a + b;
}

I64 Sub(I64 x, I64 y) {
    return x - y;
}

I64 Mul(I64 a, I64 b) {
    return a * b;
}

U0 Main() {
    I64 sum = Add(10, 20);
    I64 diff = Sub(100, 30);
    I64 prod = Mul(5, 6);
    
    "Sum: %d\n", sum;
    "Diff: %d\n", diff;
    "Prod: %d\n", prod;
}
