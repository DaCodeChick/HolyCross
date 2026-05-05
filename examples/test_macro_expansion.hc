// Test general macro expansion with values

#define MAX_SIZE 100
#define PI 3.14159
#define GREETING "Hello"

U0 TestMacros() {
    I64 size = MAX_SIZE;
    F64 pi_value = PI;
}

U0 Main() {
    TestMacros();
}
