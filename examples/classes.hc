// HolyC Class and Union Declaration Examples
// Demonstrates all class/union declaration syntax supported by the parser

// ============================================================================
// SIMPLE CLASS DECLARATIONS
// ============================================================================

// Basic class
class Point {
    I64 x;
    I64 y;
};

// Class with more members
class Rectangle {
    I64 x;
    I64 y;
    I64 width;
    I64 height;
};

// ============================================================================
// CLASS WITH REPRESENTATION TYPE
// ============================================================================

// Representation type allows casting between class and primitive type
// This is NOT inheritance - it's about memory layout and casting
I64 class CDate {
    U32 time;
    I32 date;
};

// Another example with U64
U64 class TaskHandle {
    U64 internal_id;
};

// ============================================================================
// CLASS WITH VISIBILITY MODIFIERS
// ============================================================================

// Public class
public class PublicData {
    I64 value;
};

// Static class
static class InternalData {
    I64 secret;
};

// Extern class (defined elsewhere)
extern class ExternalClass {
    I64 data;
};

// ============================================================================
// CLASS INHERITANCE
// ============================================================================

// Base class
class Base {
    I64 base_value;
};

// Derived class (true inheritance using colon)
class Derived : Base {
    I64 derived_value;
};

// Multi-level inheritance
class GrandChild : Derived {
    I64 grandchild_value;
};

// ============================================================================
// COMPLEX CLASS SYNTAX
// ============================================================================

// Public class with representation type
public I64 class PublicCDate {
    U32 time;
    I32 date;
};

// Static class with representation type
static U32 class InternalHandle {
    U32 id;
};

// ============================================================================
// UNION DECLARATIONS
// ============================================================================

// Simple union
union Value {
    I64 as_int;
    F64 as_float;
    U64 as_uint;
};

// Representation type class (like TempleOS CDate)
// The I64 before 'class' means this class can be treated as an I64
// time and date are sequential fields (time at offset 0, date at offset 4)
// Together they form an I64 value
I64 class PackedDate {
    U32 time;
    I32 date;
};

// Union for type punning
union FloatBits {
    F64 float_val;
    U64 int_bits;
};

// ============================================================================
// ALIAS SYNTAX (typedef-like) - NOT YET SUPPORTED
// ============================================================================

// NOTE: HolyC alias syntax "alias_name union Name" is not yet implemented
// This syntax would create both the alias and the original type name

// TODO: Implement alias syntax support in parser
/*
U16i union U16 {
    I8 i8[2];
    U8 u8[2];
};

U32i union U32 {
    I16 i16[2];
    U16 u16[2];
    I8  i8[4];
    U8  u8[4];
};

U64i union U64 {
    I32 i32[2];
    U32 u32[2];
    I16 i16[4];
    U16 u16[4];
    I8  i8[8];
    U8  u8[8];
};
*/

// ============================================================================
// CLASSES WITH DIFFERENT MEMBER TYPES
// ============================================================================

class ComplexData {
    I8  byte_val;
    I16 short_val;
    I32 int_val;
    I64 long_val;
    U8  ubyte_val;
    U16 ushort_val;
    U32 uint_val;
    U64 ulong_val;
    F64 double_val;
};

// Class with pointers
class Node {
    I64 data;
    Node* next;
    Node* prev;
};

// Class with arrays
class Buffer {
    U8 data[256];
    I64 size;
    I64 capacity;
};

// ============================================================================
// NESTED STRUCTURES (using classes)
// ============================================================================

class Inner {
    I64 value;
};

class Outer {
    Inner inner;
    I64 outer_value;
};

// ============================================================================
// REAL-WORLD EXAMPLES
// ============================================================================

// Task structure (like in TempleOS)
class CTask {
    U64 task_id;
    U8* task_name;
    I64 priority;
    CTask* next_task;
};

// File structure
class CFile {
    U8* filename;
    I64 size;
    U64 cluster;
    I64 flags;
};

// Device structure  
class CDev {
    U8* dev_name;
    I64 base_address;
    I64 irq_num;
};

// Date/Time (from TempleOS Kernel)
public I64 class CDateStruct {
    U32 time;  // Time in format used by DOS
    I32 date;  // Date in format used by DOS
};

// ============================================================================
// CLASSES FOR TYPE-SAFE HANDLES
// ============================================================================

// Type-safe handle pattern
U64 class WindowHandle {
    U64 handle;
};

U64 class FileHandle {
    U64 handle;
};

U64 class ProcessHandle {
    U64 handle;
};

// ============================================================================
// UNIONS FOR BIT MANIPULATION
// ============================================================================

// Color union (simple flat members)
union Color {
    U32 value;
    U8 r;
    U8 g;
    U8 b;
    U8 a;
};

// CPU Flags union (simple flat members)
union CPUFlags {
    U64 value;
    U8 carry;
    U8 zero;
    U8 sign;
    U8 overflow;
};

// ============================================================================
// COMPLEX REAL-WORLD STRUCTURES
// ============================================================================

// Memory block descriptor
public class CMemBlk {
    U64 address;
    I64 size;
    I64 flags;
    CMemBlk* next;
};

// Hash table entry
class CHashEntry {
    U8* key;
    U64 hash;
    I64 value;
    CHashEntry* next;
};

// Graphics sprite
class CSprite {
    I64 x;
    I64 y;
    I64 width;
    I64 height;
    U8* pixel_data;
    I64 flags;
};

// ============================================================================
// EXAMPLE USAGE IN FUNCTIONS
// ============================================================================

Point CreatePoint(I64 x, I64 y) {
    Point p;
    p.x = x;
    p.y = y;
    return p;
}

I64 Distance(Point* p1, Point* p2) {
    I64 dx = p2->x - p1->x;
    I64 dy = p2->y - p1->y;
    return dx * dx + dy * dy; // Squared distance
}

U0 InitNode(Node* node, I64 data) {
    node->data = data;
    node->next = NULL;
    node->prev = NULL;
}

// Working with representation types
I64 DateToInt(CDate* date) {
    // Can cast CDate to I64 because of representation type
    return (I64)date;
}

CDate IntToDate(I64 value) {
    return (CDate)value;
}

// ============================================================================
// LOCAL VARIABLE USAGE EXAMPLES
// ============================================================================

// Test basic class/union variable declarations
U0 TestBasicDeclarations() {
    Point p;           // Simple class variable
    Point* ptr;        // Class pointer variable
    Rectangle rect;    // Another class type
}

// Test pointer declarations (including multi-level)
U0 TestPointers() {
    Point* p1;         // Single pointer
    Point** p2;        // Pointer to pointer
    Rectangle* rects;  // Pointer (could be array)
}

// Test mixed primitive and class declarations
U0 TestMixed() {
    I64 x;            // Primitive type
    Point p;          // Class type
    I64 y;            // Primitive type  
    Rectangle r;      // Class type
    I64* ptr;         // Primitive pointer
    Point* pptr;      // Class pointer
}

// Test sizeof with class types
I64 GetPointSize() {
    return sizeof(Point);
}

I64 GetRectSize() {
    return sizeof(Rectangle);
}

// ============================================================================
// DEMONSTRATION
// ============================================================================

U0 Main() {
    Print("Class and Union Examples\n");
    
    // Create a point
    Point p;
    p.x = 10;
    p.y = 20;
    
    // Create a node
    Node* node = MAlloc(sizeof(Node));
    InitNode(node, 42);
    
    // Use union for type punning
    FloatBits fb;
    fb.float_val = 3.14159;
    Print("Float as bits: %X\n", fb.int_bits);
    
    // Test local variable declarations
    TestBasicDeclarations();
    TestPointers();
    TestMixed();
    
    Free(node);
}
