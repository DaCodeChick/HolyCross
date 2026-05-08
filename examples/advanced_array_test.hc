// Test advanced array features
class MyClass {
    I64 values[5];
};

U0 TestArrays() {
    // Multi-dimensional concept (array of arrays)
    // Note: True multi-dim might not be in HolyC
    
    // Array in struct
    MyClass obj;
    
    // Class array member access - this might not work
    // obj.values[0] = 10;
    
    // Array of classes
    MyClass objects[3];
}

U0 Main() {
    TestArrays;
    "Advanced array test\n";
}

Main;
