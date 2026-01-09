# HolyC Keyword Reference

Complete list of all HolyC keywords as defined in TempleOS Compiler source.

**Total: 71 keywords (48 regular + 11 types + 12 assembly directives)**

## Type Keywords (11)

| Keyword | Description | Size |
|---------|-------------|------|
| `I0` | Signed zero-sized void type | 0 bytes |
| `I8` | Signed 8-bit integer | 1 byte |
| `I16` | Signed 16-bit integer | 2 bytes |
| `I32` | Signed 32-bit integer | 4 bytes |
| `I64` | Signed 64-bit integer | 8 bytes |
| `U0` | Unsigned zero-sized void type | 0 bytes |
| `U8` | Unsigned 8-bit integer | 1 byte |
| `U16` | Unsigned 16-bit integer | 2 bytes |
| `U32` | Unsigned 32-bit integer | 4 bytes |
| `U64` | Unsigned 64-bit integer | 8 bytes |
| `F64` | 64-bit floating point (double) | 8 bytes |

**Note**: HolyC has no `F32` (float) type - only `F64` (double).

## Control Flow Keywords (11)

| Keyword | Description | Example |
|---------|-------------|---------|
| `if` | Conditional statement | `if (x > 0) { }` |
| `else` | Else clause | `if (x) { } else { }` |
| `while` | While loop | `while (i < 10) { }` |
| `for` | For loop | `for (i = 0; i < 10; i++) { }` |
| `do` | Do-while loop | `do { } while (x);` |
| `switch` | Switch statement | `switch (x) { }` |
| `case` | Case label | `case 1: break;` |
| `default` | Default case | `default: break;` |
| `break` | Exit loop/switch | `break;` |
| `return` | Return from function | `return 42;` |
| `goto` | Unconditional jump | `goto label;` |

## Class/Type Keywords (5)

| Keyword | Description | Example |
|---------|-------------|---------|
| `class` | Define class/struct | `class Point { I64 x; I64 y; };` |
| `union` | Define union type | `union Data { I64 i; F64 f; };` |
| `sizeof` | Size of type/variable | `sizeof(I64)` → 8 |
| `offset` | Offset of member | `offset(Point.x)` |
| `lastclass` | Reference to last class | Used in declarations |

## Exception Handling (2)

| Keyword | Description | Example |
|---------|-------------|---------|
| `try` | Try block | `try { risky(); }` |
| `catch` | Catch exception | `catch { handle(); }` |

## Inline Assembly (1)

| Keyword | Description | Example |
|---------|-------------|---------|
| `asm` | Inline assembly block | `asm { MOV RAX, 42 }` |

## Linkage/Visibility Keywords (8)

| Keyword | Description | Usage |
|---------|-------------|-------|
| `extern` | External linkage | `extern I64 global_var;` |
| `import` | Import symbol | `import MyFunc;` |
| `public` | Public visibility | `public I64 x;` |
| `static` | Static storage class | `static I64 counter;` |
| `_extern` | Internal extern variant | Compiler internal |
| `_import` | Internal import variant | Compiler internal |
| `_intern` | Internal linkage | Compiler internal |

**Note**: Underscore-prefixed keywords are compiler internal variants.

## Function Attributes (5)

| Keyword | Description | Example |
|---------|-------------|---------|
| `interrupt` | Interrupt handler | `interrupt U0 TimerISR() { }` |
| `haserrcode` | Interrupt has error code | `interrupt haserrcode U0 PageFault() { }` |
| `argpop` | Function pops arguments | `argpop U0 MyFunc(I64 x) { }` |
| `noargpop` | Function doesn't pop args | `noargpop U0 MyFunc(I64 x) { }` |
| `lock` | Atomic lock prefix | `lock { i++; }` |

**Note**: `interrupt` is used for OS-level interrupt handlers. `lock` adds x86 LOCK prefix for multicore safety.

## Register Hints (2)

| Keyword | Description | Example |
|---------|-------------|---------|
| `reg` | Suggest register allocation | `I64 reg x = 5;` |
| `noreg` | Prevent register allocation | `I64 noreg y = 10;` |

**Note**: These are hints to the compiler's register allocator, not strict directives.

## Preprocessor Keywords (10)

| Keyword | Description | Example |
|---------|-------------|---------|
| `define` | Define macro | `#define MAX 100` |
| `defined` | Check if defined | `#ifdef defined(DEBUG)` |
| `include` | Include file | `#include "MyLib.HC"` |
| `ifdef` | If defined | `#ifdef DEBUG` |
| `ifndef` | If not defined | `#ifndef NDEBUG` |
| `ifaot` | If ahead-of-time compile | `#ifaot` |
| `ifjit` | If just-in-time compile | `#ifjit` |
| `endif` | End conditional | `#endif` |
| `assert` | Compile-time assertion | `#assert sizeof(I64) == 8` |
| `exe` | Execute at compile time | `#exe { PrintVersion; }` |

**Note**: `#exe` is a unique HolyC feature that executes code during compilation.

## Block Markers (2)

| Keyword | Description | Example |
|---------|-------------|---------|
| `start` | Start block (alternative to `{`) | `if (x) start code; end` |
| `end` | End block (alternative to `}`) | `if (x) start code; end` |

**Note**: `start`/`end` can be used instead of braces for block delimiting.

## Special Keywords (3)

| Keyword | Description | Usage |
|---------|-------------|-------|
| `no_warn` | Suppress warnings | Compiler directive |
| `help_file` | Documentation file | Documentation metadata |
| `help_index` | Documentation index | Documentation metadata |

## Assembly Directives (12)

Used within `asm { }` blocks:

| Keyword | Description | Example |
|---------|-------------|---------|
| `ALIGN` | Align data/code | `ALIGN 16` |
| `ORG` | Set origin address | `ORG 0x7C00` |
| `BINFILE` | Include binary file | `BINFILE "data.bin"` |
| `DU8` | Define unsigned 8-bit | `DU8 0x42` |
| `DU16` | Define unsigned 16-bit | `DU16 0x1234` |
| `DU32` | Define unsigned 32-bit | `DU32 0x12345678` |
| `DU64` | Define unsigned 64-bit | `DU64 0x123456789ABCDEF0` |
| `DUP` | Duplicate directive | `DU8 10 DUP(0)` |
| `USE16` | Use 16-bit mode | `USE16` |
| `USE32` | Use 32-bit mode | `USE32` |
| `USE64` | Use 64-bit mode | `USE64` |
| `LIST` | Enable assembly listing | `LIST` |
| `NOLIST` | Disable assembly listing | `NOLIST` |

**Note**: Assembly directives are UPPERCASE by convention.

## Special Identifiers (Not Keywords)

These identifiers have **special compiler treatment** but are **not reserved keywords**:

### `pad`
**Purpose**: Structure padding and alignment
**Special behavior**: The compiler allows multiple members named `pad` in the same class (duplicate name exception)
**Usage**:
```c
class MyStruct {
    U8 type;
    U8 pad[3];      // Pad to 4-byte boundary
    I64 value;
    U8 pad[56];     // Pad to cache line (64 bytes total)
};
```
**Common patterns**:
- `U8 pad[3]` - Pad by 3 bytes (4-byte alignment)
- `U8 pad[7]` - Pad by 7 bytes (8-byte alignment)
- `Bool pad[DFT_CACHE_LINE_WIDTH-1]` - Cache line alignment (128 bytes)

### `reserved`
**Purpose**: Reserved fields (similar to `pad`)
**Special behavior**: Also exempt from duplicate name checking
**Usage**: Same as `pad`, but semantically indicates "reserved for future use"

### `_anon_`
**Purpose**: Anonymous members
**Special behavior**: Exempt from duplicate name checking
**Usage**: For unnamed union/struct members

**Implementation note**: These special identifiers are handled in the compiler's `MemberAdd()` function (`Compiler/LexLib.HC`), which skips duplicate member checks for these names.

## Reserved but Not Listed

The following are **not** HolyC keywords (unlike C):
- `const` - Not used in HolyC
- `volatile` - Not used
- `continue` - Not a keyword (use `break` or restructure)
- `auto` - Not used
- `register` - Use `reg` instead
- `signed`/`unsigned` - Use I*/U* types instead
- `short`/`long` - Use specific sized types
- `void` - Use `U0` or `I0` instead

## Case Sensitivity

**Important**: HolyC keywords are **case-sensitive**:
- Type keywords: **UPPERCASE** (`I64`, `U8`, not `i64`, `u8`)
- Control flow: **lowercase** (`if`, `while`, not `IF`, `WHILE`)
- Assembly directives: **UPPERCASE** (`ALIGN`, `DU64`, not `align`, `du64`)

## Operator Keywords

HolyC also has one operator that looks like a keyword:
- **`` ` ``** (backtick) - Power operator: `2 ` 8` = 256

## Source References

**Definitive source**: TempleOS repository
- `Compiler/OpCodes.DD` - Keyword definitions
- `Compiler/CompilerA.HH` - Keyword constants (KW_* and AKW_*)
- `Compiler/Lex.HC` - Keyword parsing logic

## Lexer Implementation

In HolyCross, keywords are stored in a `StaticStringMap` for O(1) lookup:

```zig
const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "I64", .keyword_i64 },
    .{ "if", .keyword_if },
    // ... all 71 keywords
});
```

---

**Last Updated**: 2026-01-09
**Source**: TempleOS Compiler (commit: latest)
**Implementation**: HolyCross `src/lexer/lexer.zig`

---

## Lexer Implementation Notes

### What the Lexer Needs to Handle

1. **Keywords (71 total)**: 
   - Reserved identifiers that have special meaning
   - Must be recognized and returned as keyword tokens
   - Case-sensitive matching required

2. **Special Identifiers (3 total)**:
   - `pad`, `reserved`, `_anon_` 
   - NOT keywords - just regular identifiers
   - Special treatment only in **semantic analysis** (duplicate checking)
   - Lexer treats them as normal identifiers

### Implementation Strategy

```zig
// In lexer:
fn scanIdentifier(self: *Lexer) Token {
    // 1. Scan identifier characters
    const start = self.position;
    while (isIdentifierContinue(self.peek())) {
        self.advance();
    }
    const lexeme = self.source[start..self.position];
    
    // 2. Check if it's a keyword
    if (Lexer.getKeyword(lexeme)) |keyword_type| {
        return Token{ .type = keyword_type, .lexeme = lexeme, ... };
    }
    
    // 3. Otherwise, it's an identifier (including 'pad', 'reserved', '_anon_')
    return Token{ .type = .identifier, .lexeme = lexeme, ... };
}
```

### Semantic Phase Handling

The special identifiers are only special in the **parser/semantic analysis**:

```zig
// In semantic analyzer (later):
fn addMember(class: *Class, member: Member) !void {
    // Check for duplicate members
    if (class.hasMember(member.name)) {
        // EXCEPT for these special names:
        if (!std.mem.eql(u8, member.name, "pad") and
            !std.mem.eql(u8, member.name, "reserved") and
            !std.mem.eql(u8, member.name, "_anon_")) {
            return error.DuplicateMember;
        }
    }
    try class.members.append(member);
}
```

### Summary

- **Lexer**: Recognizes 71 keywords + all identifiers (including special ones)
- **Parser**: Understands structure and syntax
- **Semantic Analyzer**: Applies special duplicate-checking rules for `pad`, `reserved`, `_anon_`

---

**Version**: 1.1
**Last Updated**: 2026-01-09
**Contributors**: Research from TempleOS Compiler source analysis
