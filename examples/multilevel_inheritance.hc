// Test multi-level class inheritance
class GrandBase {
    I64 a;
};

class Base : GrandBase {
    I64 b;
};

class Derived : Base {
    I64 c;
};

U0 TestFunc(Derived obj) {
    I64 temp;
    temp = obj.a;  // Should access from GrandBase
    temp = obj.b;  // Should access from Base
    temp = obj.c;  // Should access from Derived
}

U0 Main() {
    "Multi-level inheritance test compiled successfully\n";
}
