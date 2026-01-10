// HolyC Control Flow Statements Examples
// Demonstrates all statement types supported by the parser

// ============================================================================
// BLOCK STATEMENTS
// ============================================================================

// Simple block
{
    I64 x = 1;
    I64 y = 2;
    I64 z = x + y;
}

// Nested blocks
{
    I64 outer = 100;
    {
        I64 inner = 200;
        outer = outer + inner;
    }
}

// ============================================================================
// IF STATEMENTS
// ============================================================================

// Simple if
if (x > 0)
    y = 1;

// If with block
if (x > 0) {
    y = 1;
    z = 2;
}

// If-else
if (x > 0)
    y = 1;
else
    y = 0;

// If-else with blocks
if (x > 0) {
    y = 1;
    z = 2;
} else {
    y = 0;
    z = 0;
}

// If-else chain
if (x > 10)
    y = 3;
else if (x > 5)
    y = 2;
else if (x > 0)
    y = 1;
else
    y = 0;

// Nested if statements
if (x > 0) {
    if (y > 0) {
        z = x + y;
    } else {
        z = x - y;
    }
}

// ============================================================================
// WHILE LOOPS
// ============================================================================

// Simple while
while (x < 10)
    x++;

// While with block
while (x < 10) {
    y = y + x;
    x++;
}

// Nested while
while (x < 10) {
    while (y < 5) {
        z = z + 1;
        y++;
    }
    x++;
}

// ============================================================================
// DO-WHILE LOOPS
// ============================================================================

// Simple do-while
do
    x++;
while (x < 10);

// Do-while with block
do {
    y = y + x;
    x++;
} while (x < 10);

// Nested do-while
do {
    do {
        z++;
    } while (z < 5);
    x++;
} while (x < 10);

// ============================================================================
// FOR LOOPS
// ============================================================================

// Simple for loop
for (I64 i = 0; i < 10; i++)
    sum = sum + i;

// For loop with block
for (I64 i = 0; i < 10; i++) {
    sum = sum + i;
    product = product * i;
}

// For loop with complex expressions
for (I64 i = 0; i < n * 2; i = i + 2) {
    result = result + array[i];
}

// Nested for loops
for (I64 i = 0; i < rows; i++) {
    for (I64 j = 0; j < cols; j++) {
        matrix[i * cols + j] = i + j;
    }
}

// For loop with empty parts (infinite loop-like syntax)
for (;;) {
    if (done)
        break;
}

// ============================================================================
// RETURN STATEMENTS
// ============================================================================

// Simple return
return;

// Return with value
return 42;

// Return with expression
return x + y * z;

// Return with complex expression
return (a > b) + (c < d);

// Return with function call
return Calculate(x, y, z);

// ============================================================================
// BREAK STATEMENTS
// ============================================================================

// Break in while loop
while (x < 100) {
    if (x == 50)
        break;
    x++;
}

// Break in for loop
for (I64 i = 0; i < 100; i++) {
    if (array[i] == target)
        break;
}

// Break in nested loop (breaks inner loop only)
for (I64 i = 0; i < 10; i++) {
    for (I64 j = 0; j < 10; j++) {
        if (j == 5)
            break;
    }
}

// ============================================================================
// COMPLEX COMBINATIONS
// ============================================================================

// Complex nested control flow
for (I64 i = 0; i < n; i++) {
    if (i != 0) {
        while (j < m) {
            if (array[j] >= 0) {
                if (array[j] > threshold) {
                    break;
                }
                
                do {
                    k++;
                    if (k == i) {
                        return result;
                    }
                } while (k < array[j]);
            }
            
            j++;
        }
    }
}

// Expression statements mixed with control flow
x = 10;
y = 20;

if (x < y) {
    temp = x;
    x = y;
    y = temp;
}

result = x + y;

// Function calls as statements
Calculate(x, y);
Print(result);
InitializeArray(array, size);
