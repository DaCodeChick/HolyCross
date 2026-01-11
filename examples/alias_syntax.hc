// HolyCross Compiler - Alias Syntax Example
// Demonstrates TempleOS-style type aliasing for unions and classes

// Example: U16Alias is an alias for MyU16 union
U16Alias union MyU16 {
    I8 i8[2];
    U8 u8[2];
};

// Another example: I32Alias as alias for MyI32 union
I32Alias union MyI32 {
    I8 i8[4];
    I16 i16[2];
    U8 u8[4];
    U16 u16[2];
};

// Alias syntax also works with classes
MyDateAlias class MyDate {
    U32 time;
    I32 date;
};

// Function demonstrating usage of both the alias and the main type
U0 DemoAliasUsage() {
    MyU16 val1;       // Using the main type
    U16Alias val2;    // Using the alias - should work identically
    
    MyDate date1;      // Using main class type
    MyDateAlias date2; // Using class alias
}

U0 Main() {
    "Alias syntax example compiled successfully!\n";
    DemoAliasUsage;
}
