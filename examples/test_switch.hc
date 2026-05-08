// Test switch/case statements
I64 GetDayNumber(I64 day) {
    I64 result = 0;
    switch (day) {
        case 1:
            result = 100;
            break;
        case 2:
            result = 200;
            break;
        case 3:
            result = 300;
            break;
        default:
            result = 999;
            break;
    }
    return result;
}

U0 Main() {
    I64 d1 = GetDayNumber(1);  // Should return 100
    I64 d2 = GetDayNumber(2);  // Should return 200
    I64 d3 = GetDayNumber(5);  // Should return 999 (default)
    "Switch test completed\n";
}

Main;
