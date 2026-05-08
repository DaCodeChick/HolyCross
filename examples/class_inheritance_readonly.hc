// Test class inheritance - read-only test
class Base {
    I64 x;
    I64 y;
};

class Derived : Base {
    I64 z;
};

U0 TestFunc(Derived obj) {
    I64 temp;
    temp = obj.x;  // Should access inherited member from Base
    temp = obj.y;  // Should access inherited member from Base
    temp = obj.z;  // Should access own member
}

U0 Main() {
    "Class inheritance test compiled successfully\n";
}

Main;
