// Test assignment and reading back
class Point {
    I64 x;
    I64 y;
};

extern U0 printf(U8 *fmt, ...);

U0 Main() {
    Point p;
    p.x = 10;
    printf("After first assign, p.x = %ld\n", p.x);
    p.y = 20;
    printf("After second assign, p.y = %ld\n", p.y);
    printf("p.x = %ld, p.y = %ld\n", p.x, p.y);
}

Main;
