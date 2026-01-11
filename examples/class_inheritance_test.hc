// Test class inheritance
class Base {
    I64 x;
    I64 y;
};

class Derived : Base {
    I64 z;
};

U0 Main() {
    Derived obj;
    obj.x = 10;  // Should access inherited member
    obj.y = 20;  // Should access inherited member
    obj.z = 30;  // Should access own member
}
