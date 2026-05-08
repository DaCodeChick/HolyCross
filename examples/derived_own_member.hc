// Test inherited member assignment
class Base {
    I64 x;
    I64 y;
};

class Derived : Base {
    I64 z;
};

U0 Main() {
    Derived obj;
    obj.z = 30;  // Own member should work
    "Own member works\n";
}

Main;
