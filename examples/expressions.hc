// HolyC Expression Examples
// Tests parser with various expression types

// Simple arithmetic
1 + 2
3 * 4
5 - 6
7 / 8
9 % 10

// Precedence
1 + 2 * 3
(1 + 2) * 3
2 * 3 + 4

// Power operator (HolyC-specific)
2`8
3`2`2

// Logical XOR (HolyC-specific)
a ^^ b
x ^^ y ^^ z

// Unary operators
-42
+100
!flag
~mask

// Complex expressions
-a + b * c
(x + y) * (z - w)
a * b + c * d

// Variables
my_var
x1
_internal

// Mixed literals
42 + 3.14
100 * 2.5

// Function calls
func()
add(1, 2)
calculate(x, y, z)

// Array subscript
arr[0]
matrix[i][j]
data[x + 1]

// Member access
obj.field
person.name
point.x

// Arrow operator
ptr->field
node->next
obj->value

// Postfix increment/decrement
x++
y--
counter++

// Complex postfix expressions
obj.array[i]
func(a, b).result
arr[i].field
ptr->array[0]
obj.method()
data[i].process()
list.items[index].name
