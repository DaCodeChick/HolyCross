// HolyC Function Declaration Examples
// Demonstrates all function declaration syntax supported by the parser

// ============================================================================
// SIMPLE FUNCTIONS
// ============================================================================

// Void function (U0 return type)
U0 HelloWorld() {
    I64 x = 42;  // Just a simple statement
}

// Function returning integer
I64 GetAnswer() {
    return 42;
}

// Function with single parameter
I64 Square(I64 x) {
    return x * x;
}

// Function with multiple parameters
I64 Add(I64 a, I64 b) {
    return a + b;
}

I64 Sum(I64 a, I64 b, I64 c) {
    return a + b + c;
}

// ============================================================================
// FUNCTIONS WITH DIFFERENT RETURN TYPES
// ============================================================================

U8 GetByte() {
    return 255;
}

I16 GetShort() {
    return -100;
}

U32 GetUnsignedInt() {
    return 1000000;
}

F64 GetPi() {
    return 3.14159265359;
}
// Function returning pointer - uses null since MAlloc isn't defined
I64* AllocateArray(I64 size) {
    return 0;  // Return null since MAlloc not available
}

// ============================================================================
// FUNCTIONS WITH POINTER PARAMETERS
// ============================================================================

U0 Swap(I64* a, I64* b) {
    I64 temp = *a;
    *a = *b;
    *b = temp;
}

U0 FillArray(I64* arr, I64 size, I64 value) {
    for (I64 i = 0; i < size; i++)
        arr[i] = value;
}

// ============================================================================
// FUNCTIONS WITH ARRAY PARAMETERS
// ============================================================================

I64 SumArray(I64[] arr, I64 count) {
    I64 sum = 0;
    for (I64 i = 0; i < count; i++)
        sum = sum + arr[i];
    return sum;
}

// ============================================================================
// FORWARD DECLARATIONS
// ============================================================================
// Forward declarations - NOT YET SUPPORTED
// (Functions must be defined before use)
/*
I64 Factorial(I64 n);
U0 ProcessData(I64* data, I64 size);
*/

// ============================================================================
// VISIBILITY MODIFIERS
// ============================================================================
// Public function (exported)
public U0 PublicFunction() {
    I64 x = 1;
}

// Static function (internal linkage)
static U0 InternalHelper() {
    I64 x = 2;
}

// Extern function (defined elsewhere)
extern U0 ExternalFunction();

// ============================================================================
// FUNCTION ATTRIBUTES
// ============================================================================

// Interrupt handler
interrupt U0 TimerInterrupt() {
    // Handle timer interrupt
}

// Function with error code
haserrcode U0 MayFail() {
    // Can throw errors
}

// Lock attribute
lock U0 CriticalSection() {
    // Protected code
}

// ============================================================================
// COMBINING ATTRIBUTES
// ============================================================================

public static I64 PublicStaticFunction() {
    return 100;
}

extern public U0 ExternPublicFunction();

// ============================================================================
// COMPLEX FUNCTION EXAMPLES
// ============================================================================

// Recursive function
I64 Factorial(I64 n) {
    if (n <= 1)
        return 1;
    return n * Factorial(n - 1);
}

// Function with multiple control flow
I64 Max(I64 a, I64 b) {
    if (a > b)
        return a;
    else
        return b;
}

// Function with loops
I64 Power(I64 base, I64 exp) {
    I64 result = 1;
    for (I64 i = 0; i < exp; i++)
        result = result * base;
    return result;
}

// Function with switch
U8* GetColorName(I64 color) {
    switch (color) {
        case 0:
            return "Black";
        case 1:
            return "Blue";
        case 2:
            return "Green";
        default:
            return "Unknown";
    }
}

// Function with local variables
I64 Calculate(I64 x, I64 y) {
    I64 temp1 = x * 2;
    I64 temp2 = y * 3;
    I64 result = temp1 + temp2;
    return result;
}

// ============================================================================
// NESTED BLOCKS AND COMPLEX LOGIC
// ============================================================================

U0 ComplexFunction(I64 n) {
    I64 i = 0;
    I64 result = 0;
    
    while (i < n) {
        {
            I64 temp = i * i;
            result = result + temp;
        }
        i++;
    }
    
    if (n > 10) {
        result = result * 2;
    } else {
        result = result + 1;
    }
}

// Function with try-catch - NOT YET SUPPORTED
/*
U0 SafeOperation() {
    try {
        // Risky operation
        DivideByZero();
    } catch {
        // Handle error
        I64 x = 1;
    }
}
*/

// Function with goto - NOT YET SUPPORTED
/*
U0 WithGoto(I64 condition) {
    if (condition)
        goto cleanup;
    
    // Do work
    Print("Working...\n");
    
cleanup:
    Print("Cleaning up\n");
}
*/

// ============================================================================
// MAIN FUNCTION
// ============================================================================
U0 Main() {
    I64 x = Add(5, 3);
    I64 y = Square(4);
    
    // Note: Factorial call removed because forward declarations aren't supported
    // and Factorial is defined after Main
    I64 result = x + y;
}
