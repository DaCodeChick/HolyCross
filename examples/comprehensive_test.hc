// Comprehensive test of all working features
class Point {
    I64 x;
    I64 y;
};

class Point3D : Point {
    I64 z;
};

#define MAX_VALUE 100
#define MIN_VALUE 10

U0 Main() {
    // Test member assignment
    Point p;
    p.x = MIN_VALUE;
    p.y = 20;
    
    // Test inheritance and assignment
    Point3D p3;
    p3.x = 30;  // Inherited
    p3.y = 40;  // Inherited
    p3.z = MAX_VALUE;  // Own member
    
    "All tests passed!\n";
}

Main;
