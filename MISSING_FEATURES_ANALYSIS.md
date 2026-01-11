# HolyCross Compiler - Missing Features Analysis

Based on examination of real TempleOS source code, the following features are **legitimate HolyC syntax** that should be supported but are currently missing in HolyCross:

## 1. Top-Level Statements ✅ COMPLETED

**TempleOS Usage:**
```c
U0 MyFunc() {
    "Hello\n";
}

MyFunc;  // Top-level function call - executes when file is loaded
```

**Status:** ✅ **IMPLEMENTED** - Fully working!

**Implementation:** 
- Parser modified to distinguish declarations from statements at top level
- AST Program struct now includes `top_level_stmts: []Stmt`
- IR builder creates C's `main()` that executes top-level statements before calling HolyC's `Main()`

**How it works:**
1. Top-level statements are executed when the program starts
2. If a HolyC `Main()` function exists, it's called after top-level statements
3. Program returns 0 by default

**Example:** See `examples/top_level_execution.hc`

---

## 2. Extern Forward Declarations

**TempleOS Usage (from Kernel/KernelA.HH):**
```c
extern class CAOT;
extern class CAOTHeapGlbl;
extern class CTask;
```

**Current Status:** Not supported - causes "Redeclaration" errors

**Impact:** Cannot organize code with header files properly

**Solution:** Semantic analyzer should track extern declarations separately from definitions.

---

## 3. Alias Syntax for Types

**TempleOS Usage (from Kernel/KernelA.HH):**
```c
U16i union U16 {
    I8i i8[2];
    U8i u8[2];
};
```

This creates **both** the alias `U16` and marks it with the `i` suffix for certain behaviors.

**Current Status:** Not supported - parser error "Expected declaration"

**Impact:** Cannot define standard library types correctly

**Solution:** Parser needs to handle `identifier union/class TypeName { ... }` syntax.

---

## 4. Top-Level Preprocessor Directives

**TempleOS Usage (from Kernel/KernelA.HH):**
```c
#define NULL 0
#define TRUE 1
#define FALSE 0
#define STR_LEN 144
```

**Current Status:** Parser error "Expected declaration" for top-level #define

**Impact:** Cannot use standard library constants

**Solution:** Preprocessor should process #define before parsing

---

## 5. Array Members in Classes

**TempleOS Usage (from Kernel/KernelA.HH):**
```c
#define QUE_VECT_U8_CNT 512
public class CQueVectU8 {
    CQueVectU8 *next, *last;
    I64 total_cnt, node_cnt, min_idx;
    U8 body[QUE_VECT_U8_CNT];  // Array member
};
```

**Current Status:** Parser error "Expected ';' after member declaration"

**Impact:** Cannot define data structures with fixed-size buffers

**Solution:** Parser needs to support array syntax in class/union members.

---

## 6. Variable Arrays (Syntax: Type name[size])

**Current Status:** Parser error for declarations like `I64 arr[10];`

**Impact:** Basic C-style arrays not usable

**Solution:** Parser needs to handle subscript after identifier in declarations.

---

## 7. Class Inheritance Syntax

**TempleOS Usage:**
```c
public I64 class CDate {
    U32 time;
    I32 date;
};
```

The `I64 class CDate` means CDate inherits from/aliases I64.

**Current Status:** Unknown if supported

**Solution:** Investigate parser support for type prefix before `class` keyword.

---

## Recommendations for HolyCross Development

### Priority 1 (Core Features):
1. ✅ **Top-level statements** - COMPLETED! See examples/top_level_execution.hc
2. ⬜ **extern declarations** - Needed for multi-file projects
3. ⬜ **Array syntax** - Basic feature used everywhere

### Priority 2 (Standard Library Compatibility):
4. **Alias syntax** (U16i union U16) - Needed for stdlib
5. **Top-level #define** - Needed for constants
6. **Array members in classes** - Common pattern

### Priority 3 (Advanced):
7. **Class inheritance/alias syntax** - Less common

---

## Example Files That Were "Over-Fixed"

The following example files were modified to work around missing features, but actually contain **valid HolyC syntax**:

- `expressions.hc` - Could have top-level expression statements
- `statements.hc` - Could have top-level statement blocks  
- `variables.hc` - Could have top-level variable declarations
- `preprocessor_example.hc` - Could have top-level #define
- `classes.hc` - Should support alias syntax and array members

These files should be **restored** once the compiler supports these features properly.

---

## Reference

Real TempleOS source examined:
- `/home/admin/Downloads/TempleOS-archive/Kernel/KernelA.HH`
- `/home/admin/Downloads/TempleOS-archive/Once.HC`
- `/home/admin/Downloads/TempleOS-archive/Demo/Carry.HC`
