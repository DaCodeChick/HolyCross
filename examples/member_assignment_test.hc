// Test member assignment
class Point {
    I64 x;
    I64 y;
};

U0 Main() {
    Point p;
    p.x = 10;  // This should work but currently fails
    p.y = 20;
    "Member assignment test\n";
}
