// Test simple while loop
U0 Main() {
    I64 sum = 0;
    I64 i = 0;
    while (i < 5) {
        sum = sum + i;
        i = i + 1;
    }
    // sum should be 0+1+2+3+4 = 10
}

Main;
