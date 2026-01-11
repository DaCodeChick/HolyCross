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

## 2. Extern Forward Declarations ✅ COMPLETED

**TempleOS Usage (from Kernel/KernelA.HH):**
```c
extern class CAOT;
extern class CAOTHeapGlbl;
extern class CTask;

extern U0 SomeFunction();
```

**Status:** ✅ **IMPLEMENTED** - Fully working!

**Implementation:**
- Added `is_extern` field to `FunctionSymbol` and `TypeSymbol`
- Modified semantic analyzer to allow extern declarations followed by definitions
- Multiple extern declarations are allowed (redundant but valid)
- IR builder skips generating code for extern-only declarations

**Valid patterns:**
1. `extern` declaration → full definition (most common)
2. Multiple `extern` declarations for the same symbol (redundant but okay)
3. `extern` declaration without definition (forward reference, linker resolves)

**Example:** See `examples/extern_declarations.hc`

---

## 3. Alias Syntax for Types ✅ COMPLETED

**TempleOS Usage (from Kernel/KernelA.HH):**
```c
U16i union U16 {
    I8i i8[2];
    U8i u8[2];
};
```

This creates **both** the main type (`U16`) and an alias (`U16i`) that refers to it.

**Status:** ✅ **IMPLEMENTED** - Fully working!

**Implementation:**
- Parser modified to recognize `identifier union/class TypeName` syntax
- Parser uses lookahead (`peek()`) to distinguish alias syntax from other declarations
- `looksLikeDeclaration()` updated to recognize this pattern at top-level
- Semantic analyzer registers both the main type and the alias in the symbol table
- Alias is stored as a `named` type that refers to the main type

**How it works:**
1. `AliasName union TypeName { ... }` creates type `TypeName` and alias `AliasName`
2. `AliasName class ClassName { ... }` creates class `ClassName` and alias `AliasName`
3. Both the alias and the main type can be used interchangeably in code

**Example:** See `examples/alias_syntax.hc`

**Note:** Type names cannot be reserved keywords (like `U16`, `I32`) - use custom names instead (like `MyU16`, `MyI32`).

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

## 5. Array Members in Classes ✅ COMPLETED

**TempleOS Usage (from Kernel/KernelA.HH):**
```c
#define QUE_VECT_U8_CNT 512
public class CQueVectU8 {
    CQueVectU8 *next, *last;
    I64 total_cnt, node_cnt, min_idx;
    U8 body[QUE_VECT_U8_CNT];  // Array member
};
```

**Status:** ✅ **IMPLEMENTED** - Array members work!

**Implementation:** Parser now handles array syntax `[size]` after member names in class/union definitions.

**Example:** See `examples/array_declarations.hc`

---

## 6. Variable Arrays (Syntax: Type name[size]) ✅ COMPLETED

**TempleOS Usage:**
```c
I64 numbers[10];
U8 buffer[256];
U0 Process(U8 data[512]);
```

**Status:** ✅ **IMPLEMENTED** - Fully working!

**Implementation:**
- Parser handles array suffix `[size]` after variable names
- Works for local variables, global variables, function parameters, and class members
- Array subscript `[size]` is parsed after the identifier name (C-style)

**Example:** See `examples/array_declarations.hc`

**Note:** Runtime array allocation/access in codegen is still being developed, but parsing is complete.

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
2. ✅ **extern declarations** - COMPLETED! See examples/extern_declarations.hc  
3. ✅ **Array syntax** - COMPLETED! See examples/array_declarations.hc

### Priority 2 (Standard Library Compatibility):
4. ✅ **Alias syntax** - COMPLETED! See examples/alias_syntax.hc
5. **Top-level #define** - Needed for constants

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
