# HolyC Syntax Discoveries - Session Notes

**Date**: 2026-01-09  
**Session**: Phase 2 Parser Development

## Key Discoveries

### 1. Ternary Operator - ❌ NOT SUPPORTED

**Question Raised**: Does HolyC support the ternary operator `condition ? true_val : false_val`?

**Status**: ✅ **CONFIRMED - NOT SUPPORTED**  
**Verified By**: User confirmation (2026-01-10)  
**Action Taken**: Removed ternary operator from AST (`src/parser/ast.zig`)  

**Note**: While common in C/C++, HolyC does not include the ternary conditional operator. Use if-else statements instead.

---

### 2. Class/Union Representation Type Syntax ✅ CONFIRMED

**Discovery**: HolyC has unique syntax for type representation

#### Syntax Pattern
```c
[visibility] [repr_type] [alias] class/union Name [: Base] { members }
```

#### Examples from TempleOS

**Representation Type** (Kernel/KernelA.HH:186):
```c
public I64 class CDate {
    U32 time;
    I32 date;
};
```

**Interpretation**:
- `public` = visibility modifier
- `I64` = **representation type** (NOT inheritance)
- `class` = keyword
- `CDate` = class name

**What it means**:
- CDate has same size as I64 (8 bytes)
- Can be cast/represented as I64
- Type-safe wrapper around primitive
- Ensures memory layout compatibility

**Alias Syntax** (Kernel/KernelA.HH, multiple locations):
```c
U16i union U16 {
    I8i i8[2];
    U8i u8[2];
};
```

**Interpretation**:
- `U16i` = type alias (typedef-like)
- `union` = keyword
- `U16` = union name
- Creates both U16 and alias U16i

#### True Inheritance (Different!)

```c
class Base {
    I64 value;
};

class Derived : Base {
    U8 extra;
};
```

**Key difference**: Inheritance uses **colon** (`:`) syntax, NOT a type before the keyword.

#### Why This Matters

**Wrong understanding** (initial):
```c
I64 class MyClass  →  "MyClass inherits from I64"
```

**Correct understanding**:
```c
I64 class MyClass  →  "MyClass can be represented as I64"
```

**Implications**:
1. Representation type is about **memory layout** and **casting**
2. Inheritance is about **OOP hierarchy** (uses colon)
3. Representation type works with both classes AND unions
4. Common for systems programming (type-safe primitives)

#### Real-World Use Cases

**Type-safe handles**:
```c
U64 class TaskHandle {
    U64 internal_id;
};
// Can cast TaskHandle ↔ U64 safely
```

**Union with representation**:
```c
I64 union PackedDate {
    struct {
        U32 time;
        I32 date;
    };
    I64 raw;
};
// Union is I64-sized, can be passed as I64
```

---

### 3. Complete Class/Union Syntax

#### Full Syntax Options

1. **Simple**:
   ```c
   class Foo { };
   ```

2. **With visibility**:
   ```c
   public class Foo { };
   static class Foo { };
   extern class Foo { };
   ```

3. **With representation type**:
   ```c
   I64 class Foo { };
   U32 union Foo { };
   ```

4. **With alias (typedef-like)**:
   ```c
   FooPtr class Foo { };
   ```

5. **With inheritance**:
   ```c
   class Foo : Base { };
   ```

6. **Everything combined**:
   ```c
   public I64 FooAlias class Foo : Base { };
   ```
   - `public` = visibility
   - `I64` = representation type
   - `FooAlias` = alias name
   - `Foo` = class name
   - `Base` = base class (inheritance)

#### Parser Implementation Strategy

**Parsing order**:
1. Check for visibility keywords (`public`, `static`, `extern`)
2. If next token is a type → representation type
3. If next token is identifier before class/union → alias
4. Parse `class` or `union` keyword
5. Parse class/union name
6. Check for `:` → base class (inheritance)
7. Parse body `{ members }`

**Disambiguation**:
- Visibility keywords are reserved → easy to detect
- Representation type: check if identifier is known type
- Alias: anything else before class/union keyword
- May need symbol table for type checking

---

## Impact on Implementation

### AST Changes
```zig
class: struct {
    name: []const u8,
    alias: ?[]const u8,           // NEW: typedef-like
    repr_type: ?Type,              // RENAMED: was base_type
    base_class: ?[]const u8,       // NEW: true inheritance
    is_public: bool,
    is_static: bool,               // NEW
    is_extern: bool,               // NEW
    members: []ClassMember,
    loc: SourceLocation,
}
```

### Parser Requirements
1. Symbol table for type lookup
2. Multi-token lookahead for disambiguation
3. Handle all visibility modifiers
4. Distinguish representation vs inheritance
5. Support alias syntax

---

## Documentation Updates

### Files Modified
- `docs/KEYWORDS.md` - Added comprehensive class/union syntax section
- `src/parser/ast.zig` - Corrected field names and comments
- Created this notes file

### New Sections in KEYWORDS.md
1. Standard class/union syntax
2. Visibility modifiers
3. Representation type (with examples)
4. True inheritance (colon syntax)
5. Type alias syntax
6. Parser implementation notes

---

## Questions Remaining

1. ✅ **Representation type** - CONFIRMED (user corrected our interpretation)
2. ✅ **Ternary operator** - CONFIRMED NOT SUPPORTED (removed from AST)
3. ❓ **Multiple visibility modifiers** - Can you combine `public static`?
4. ❓ **Representation + inheritance** - Can you have both?
   ```c
   I64 class Foo : Base { }  // Valid?
   ```
5. ❓ **Alias + inheritance** - Can you have both?
   ```c
   FooPtr class Foo : Base { }  // Valid?
   ```

---

## Next Steps

### Immediate
- [ ] Verify ternary operator in TempleOS source
- [ ] Study more class declarations in Kernel/KernelA.HH
- [ ] Look for examples of representation + inheritance combined

### Parser Implementation (Phase 2)
- [ ] Implement class/union declaration parsing
- [ ] Handle all syntax variations
- [ ] Add symbol table for type resolution
- [ ] Test with real TempleOS examples

### Lexer (Separate Task)
- [ ] Consider refactoring into modules (see LEXER_REFACTOR.md)

---

## Lessons Learned

1. **Don't assume C/C++ semantics** - HolyC has unique syntax
2. **User analysis is valuable** - Caught major conceptual error
3. **Study actual source** - TempleOS code is the ground truth
4. **Document discoveries** - These patterns aren't well documented elsewhere
5. **Multiple interpretations** - Syntax can be ambiguous without context

---

## References

**TempleOS Source**:
- `Kernel/KernelA.HH:186` - `public I64 class CDate`
- `Kernel/KernelA.HH` (various) - `U16i union U16` patterns
- `Compiler/CompilerA.HH` - Grammar and parsing logic
- `Compiler/LexLib.HC` - Type and class handling

**HolyCross Implementation**:
- `src/parser/ast.zig` - AST node definitions
- `docs/KEYWORDS.md` - Complete syntax reference
- `docs/LEXER_REFACTOR.md` - Refactoring plan

---

**Credit**: Major thanks to user for catching the representation type vs inheritance distinction. This is a critical semantic difference that would have caused bugs in code generation.
