// Test assignment and reading back - simpler
class Point {
    I64 x;
    I64 y;
};

U0 Main() {
    Point p;
    p.x = 10;
    p.y = 20;
    // Just try to read them back - if we segfault, it's during read
    I64 a;
    I64 b;
    a = p.x;
    b = p.y;
}

Main;
