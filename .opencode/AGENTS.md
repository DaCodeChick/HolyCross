# Agent Knowledge Base for HolyCross

This document contains critical information for AI agents working on the HolyCross project. Reading this file will save significant time and prevent common pitfalls.

## Project Overview

**HolyCross** is a HolyC/TempleOS-compatible compiler toolchain written in Zig 0.16.0, targeting both Linux x64 ELF and TempleOS binary formats.

- **Language**: Zig 0.16.0
- **License**: MIT
- **Architecture**: Split CLI tools (hcc, hcpp, hcas) + shared libraries
- **Build System**: Zig build (`build.zig`)
- **Target**: x64 Linux (ELF) and TempleOS binary formats
- **Syntax**: TempleOS-style HolyC with modern tooling

## CRITICAL: Zig 0.16 API Gotchas

### ArrayList (Unmanaged) - MOST COMMON ISSUE

Zig 0.16 has TWO ArrayList types:
1. **`std.ArrayList(T)`** → Maps to `array_list.Aligned` (UNMANAGED - no allocator field)
2. **`std.ArrayListManaged(T)`** → Has allocator field

We use the **unmanaged** version throughout this project. Here's the correct usage:

#### ✅ CORRECT Usage

```zig
// Initialization
var list: std.ArrayList(u32) = .empty;
defer list.deinit(allocator);

// Append
try list.append(allocator, value);

// Access
for (list.items) |item| { ... }

// Pop (returns optional!)
const item = list.pop() orelse unreachable;  // or use if/while

// To owned slice
const owned = try list.toOwnedSlice(allocator);
```

#### ❌ WRONG Usage (Will Not Compile)

```zig
// DON'T DO THIS - .init() doesn't exist for unmanaged
var list = std.ArrayList(u32).init(allocator);

// DON'T DO THIS - old struct literal syntax
var list: std.ArrayList(u32) = .{ .items = &.{}, .capacity = 0 };

// DON'T DO THIS - missing allocator in deinit
defer list.deinit();

// DON'T DO THIS - missing allocator in append
try list.append(value);

// DON'T DO THIS - pop() returns optional!
const item = list.pop();  // Type error if you expect non-optional
```

#### Important Details

- **`pop()` returns `?T`** (optional) in Zig 0.16, even for unmanaged ArrayList
- Always unwrap with `orelse`, `.?`, or `if` statement
- Use `while (list.items.len > 0)` check, then `list.pop() orelse unreachable` is safe

#### Migration Pattern

When you see old-style ArrayList code, replace it:

```zig
// OLD (Zig < 0.13)
var list = std.ArrayList(u32).init(allocator);

// NEW (Zig 0.16)
var list: std.ArrayList(u32) = .empty;
```

### std.Io Interface (File I/O)

Zig 0.16 uses `std.Io` interface pattern:

```zig
var threaded = std.Io.Threaded.init(allocator, .{});
const io = threaded.io();

const stdout_file = std.Io.File.stdout();
var write_buffer: [8192]u8 = undefined;
var writer = stdout_file.writer(io, &write_buffer);

try writer.interface.print("Hello {s}\n", .{"world"});
try writer.flush();
```

Don't use old `std.fs.File.writer()` pattern.

#### Simpler Pattern for stdout (Zig 0.16+)

For simple console output, you can use `writeStreamingAll`:

```zig
pub fn main(init: std.process.Init) !void {
    try std.Io.File.stdout().writeStreamingAll(init.io, "Hello, World!\n");
}
```

**Note**: This requires main to use `std.process.Init` signature.

### AutoHashMap

AutoHashMap works normally - no special changes needed:

```zig
var map = std.AutoHashMap(u32, Value).init(allocator);
defer map.deinit();

try map.put(key, value);
const val = map.get(key);
```

### StringHashMap

StringHashMap is commonly used in this project:

```zig
var map = std.StringHashMap(Label).init(allocator);
defer map.deinit();

try map.put(key_string, value);
const val = map.get(key_string);
```

## Project Structure

```
HolyCross/
├── src/
│   ├── main.zig               # hcc - HolyC compiler CLI
│   ├── lib.zig                # Shared module exports
│   ├── tools/
│   │   ├── hcpp.zig           # Preprocessor CLI
│   │   └── hcas.zig           # Assembler CLI
│   ├── lexer/                 # Tokenization
│   ├── parser/                # AST generation
│   ├── semantic/              # Type checking, validation
│   ├── codegen/               # IR + code generation
│   │   ├── ir.zig             # IR opcodes
│   │   ├── ir_builder.zig     # IR generation
│   │   ├── x64.zig            # TempleOS-style text assembly
│   │   ├── x64_machine_code.zig  # Direct machine code
│   │   └── elf_writer.zig     # ELF output
│   ├── preprocessor/          # Macro expansion, #directives
│   ├── assembler/             # x64 assembler
│   │   ├── assembler.zig      # Interface
│   │   └── x64.zig            # x64 implementation
│   └── utils/                 # Errors, helpers
├── examples/                  # Test HolyC files
├── build.zig                  # Zig build configuration
└── ASSEMBLY_AUDIT.md          # Tool split plan
```

## Code Architecture

### Toolchain Split

HolyCross is split into three CLI tools:

1. **hcc** - HolyC Compiler
   - Orchestrates preprocessing, compilation, and assembly
   - Emits text assembly (TempleOS style) or machine code
   - Entry point: `src/main.zig`

2. **hcpp** - HolyC Preprocessor
   - Macro expansion (`#define`, `#ifdef`, etc.)
   - Include file handling (`#include`)
   - Conditional compilation
   - Entry point: `src/tools/hcpp.zig`

3. **hcas** - HolyC Assembler
   - Parses TempleOS-style x64 assembly
   - Encodes to machine code
   - Outputs ELF objects, raw binary, or hex dump
   - Entry point: `src/tools/hcas.zig`

All tools share common modules via `src/lib.zig`.

### HolyC Language Features

**TempleOS Compatibility:**
- `I0` / `U0` synonyms for `void`
- `pad` / `reserved` synonyms for alignment padding
- Zero-arg function calls use bare identifier: `Foo;` (not `Foo()`)
- **No `continue` keyword** (use different loop structure)
- No ternary operator (`? :`)
- Top-level statement execution (like scripting)
- **No `F32` type** - TempleOS has F64 only, no float
- **No `#undef`** - TempleOS doesn't support undefining macros
- **No `#pragma`** - TempleOS doesn't use pragma directives

**Calling Convention:**
- System V AMD64 ABI for Linux
- Parameters in RDI, RSI, RDX, RCX, R8, R9
- Return value in RAX
- x87 FPU for floats (ST0), not SSE

**Type System:**
- Weak typing (like C, but more permissive)
- Function call argument count is validated
- Subscript indices must be integers
- Cast operations supported

### Assembly Syntax

**TempleOS-style text assembly:**

```asm
//Label types
_FunctionName::      // Exported label
@@local_label:       // Local label
regular_label:       // Internal label

//Instructions (uppercase mnemonics)
MOV     RAX,RBX
ADD     RAX,5
CALL    Function
JMP     @@loop
PUSH    RBP
POP     RBP
RET

//Memory operands (size from registers)
MOV     RAX,[RBP-8]
MOV     [RBP-16],RDX

//Type-prefixed memory operands
MOV     RAX, I64 [RBP-8]     // Explicit 64-bit signed
FLD     F64 [RBP-16]         // Load 64-bit float
FILD    I32 [RBP-4]          // Load 32-bit integer to FPU
MOV     AL, U8 [RSI]         // Load unsigned byte
```

**Key differences from AT&T/Intel:**
- Uppercase mnemonics
- No size suffixes like MOVL, MOVQ (inferred from registers or type prefix)
- Type prefixes use I8/U8, I16/U16, I32/U32, I64/U64, F64 (not BYTE, WORD, DWORD, QWORD)
- Operands separated by commas with whitespace
- Comments start with `//`

### Assembler Implementation (src/assembler/x64.zig)

The assembler has two main phases:

1. **Parse** (`parse()`) - Text assembly → Instructions
   - Label extraction
   - Mnemonic recognition
   - Operand parsing (registers, immediates, memory, labels)

2. **Encode** (`encode()`) - Instructions → Machine code
   - Instruction encoding (MOV, PUSH, POP, CALL, JMP, arithmetic, etc.)
   - ModR/M byte generation for memory operands
   - REX prefix handling for x64 registers
   - Label resolution (placeholders for forward references)

**Memory Operand Encoding:**

The assembler supports memory operands like `[RBP-8]`, `[RAX+RBX*4]`, etc.

Helper function `encodeModRM()` generates ModR/M and SIB bytes:
- Handles base + displacement (e.g., `[RBP-16]`)
- Handles SIB byte for RSP/R12 (always need SIB)
- Encodes disp8 (1 byte) or disp32 (4 bytes)

**Important:** RBP as base with zero displacement requires disp32 encoding.

### IR (Intermediate Representation)

Located in `src/codegen/ir.zig`:

**Opcodes:**
- Arithmetic: `add`, `sub`, `mul`, `imul`, `div`, `idiv`, `neg`
- Logical: `and`, `or`, `xor`, `log_and`, `log_or`, `log_xor`, `log_not`, `not`
- Bitwise: `shl`, `shr`, `sar`
- Float: `fadd`, `fsub`, `fmul`, `fdiv`, `fneg`
- Memory: `load`, `store`, `load_addr`, `load_param`
- Control: `jmp`, `jmp_if`, `call`, `ret`, `label`
- Data: `load_const`, `cast`, `move`

**Operand Types:**
- Register: Virtual registers (`v0`, `v1`, etc.)
- Constant: Immediate values
- Label: Jump/call targets

### Code Generation Pipeline

1. **Preprocessing** (`src/preprocessor/`)
   - Macro expansion
   - Include file handling
   - `#ifdef` / `#ifndef` / `#else` / `#endif`
   - `#define` (TempleOS has no `#undef`)
   - `#assert` directive

2. **Lexical Analysis** (`src/lexer/`)
   - Tokenization
   - Keyword recognition
   - Identifier/literal parsing

3. **Parsing** (`src/parser/`)
   - AST generation
   - Label parsing (identifier + colon lookahead)
   - Bare call syntax (`Foo;` → call expression)

4. **Semantic Analysis** (`src/semantic/`)
   - Function call validation
   - Type checking (weak, but enforces arg counts)
   - Subscript validation
   - Error messages with source locations

5. **IR Generation** (`src/codegen/ir_builder.zig`)
   - AST → IR opcodes
   - Constant folding
   - Wrapper `main()` function generation

6. **Code Generation** (Two backends)
   - **Text Assembly**: `src/codegen/x64.zig` → TempleOS-style `.asm`
   - **Machine Code**: `src/codegen/x64_machine_code.zig` → Direct bytes

7. **Binary Output**
   - **ELF**: `src/codegen/elf_writer.zig` → `.o` or executable
   - **TempleOS**: `src/codegen/templeos_bin.zig` → `.BIN` format (future)

## Memory Management

- **Primary allocator**: Passed from main (usually arena or GPA)
- **Pattern**: Create allocator at top level, pass down
- **Cleanup**: Defer `deinit()` at allocation site

```zig
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    
    try list.append(allocator, 42);
}
```

## Building and Running

```bash
# Build all tools
zig build

# Executables
./zig-out/bin/hcc      # Compiler
./zig-out/bin/hcpp     # Preprocessor
./zig-out/bin/hcas     # Assembler

# Compile HolyC to assembly
./zig-out/bin/hcc -S examples/test_params.hc -o output.asm

# Compile HolyC to executable
./zig-out/bin/hcc examples/test_params.hc -o output

# Preprocess only
./zig-out/bin/hcpp -DDEBUG input.hc -o output.i

# Assemble text assembly
./zig-out/bin/hcas code.asm -o code.o
./zig-out/bin/hcas code.asm -f bin -o code.bin
./zig-out/bin/hcas code.asm -f hex -o code.hex
```

## Common Tasks

### Adding a New IR Opcode

1. Add variant to `Opcode` enum in `src/codegen/ir.zig`
2. Handle in `ir_builder.zig` (IR generation)
3. Handle in `x64.zig` (text assembly)
4. Handle in `x64_machine_code.zig` (machine code)

### Adding a New Instruction to Assembler

1. Add encoding logic to `encodeInstruction()` in `src/assembler/x64.zig`
2. Follow existing pattern (check operand types, emit REX prefix, emit opcode, emit ModR/M)
3. Test with `hcas` CLI

### Fixing Build Errors

**"ArrayList has no member 'init'"**
→ Use `var list: std.ArrayList(T) = .empty;` not `.init(allocator)`

**"Expected allocator parameter"**
→ Add allocator to `.append()`, `.deinit()`, etc.

**"Unused function parameter 'self'"**
→ Change `self` to `_` or use it

**"Invalid operand type"**
→ Check instruction encoding logic (likely missing operand combination)

## Testing

Run tests:

```bash
zig build test
```

Manual testing with examples:

```bash
./zig-out/bin/hcc examples/test_params.hc && ./examples/test_params
./zig-out/bin/hcc examples/test_float_arithmetic.hc
./zig-out/bin/hcc examples/test_casting.hc
```

## Git Workflow

- Main branch: `main`
- Commit style: Descriptive messages
- Always run `zig build` before committing

```bash
zig build
git add <files>
git commit -m "Add memory operand support for MOV instruction"
git push
```

## Completed Features

- ✅ Lexer / tokenizer
- ✅ Parser (AST generation)
- ✅ Semantic analyzer (type checking, validation)
- ✅ IR generation with constant folding
- ✅ Text assembly backend (TempleOS-style)
- ✅ Machine code backend (direct x64 encoding)
- ✅ ELF writer (native Linux executables)
- ✅ Preprocessor (`#define`, `#ifdef`, `#include`, `#assert`)
- ✅ Label/goto support
- ✅ Cast support
- ✅ x87 FPU float support (TempleOS-compatible)
- ✅ Standalone preprocessor tool (hcpp)
- ✅ Standalone assembler tool (hcas)
- ✅ MOV memory operand support
- ✅ Arithmetic/logical operations
- ✅ Jump instructions
- ✅ Function calls (register and label)
- ✅ Inline assembly support (`asm { }` blocks)
- ✅ `sizeof()` and `offset()` compile-time intrinsics
- ✅ Type layouts in inline assembly expressions

### Assembler Instruction Set (96 instructions)

**Data Movement:**
- MOV, MOVSX, MOVZX, LEA, XCHG, PUSH, POP

**Arithmetic:**
- ADD, SUB, IMUL, MUL, IDIV, DIV, INC, DEC, NEG

**Logical:**
- AND, OR, XOR, NOT

**Shift/Rotate:**
- SHL, SHR, SAR, ROL, ROR, RCL, RCR

**Bit Operations:**
- BT, BTC, BTR, BTS, BSF, BSR, BSWAP

**Control Flow:**
- CALL, RET, JMP, JE, JNE, JZ, JNZ, JL, JLE, JG, JGE, JA, JAE, JB, JBE, JC, JNC, JO, JNO, JS, JNS, JP, JNP, LOOP

**CPU Information:**
- RDTSC (read timestamp counter)
- CPUID (CPU identification)

**x87 FPU (68 instructions):**

*Data Transfer:*
- FLD, FST, FSTP, FILD, FIST, FISTP, FXCH

*Arithmetic:*
- FADD, FADDP, FSUB, FSUBP, FMUL, FMULP, FDIV, FDIVP
- FSUBR, FSUBRP, FDIVR, FDIVRP (reverse operations)
- FIADD, FISUB, FIMUL, FIDIV (integer operands)

*Comparison:*
- FCOM, FCOMP, FCOMPP, FUCOM, FUCOMP, FUCOMPP
- FCOMI, FCOMIP, FTST, FXAM

*Transcendental:*
- FSIN, FCOS, FSINCOS, FPTAN, FPATAN
- F2XM1, FYL2X, FYL2XP1, FSCALE

*Constants:*
- FLD1, FLDZ, FLDPI, FLDL2E, FLDL2T, FLDLG2, FLDLN2

*Arithmetic Helpers:*
- FABS, FCHS, FSQRT, FRNDINT, FXTRACT

*Control/State:*
- FINIT, FNINIT, FCLEX, FNCLEX, FNOP, WAIT
- FLDCW, FNSTCW, FSTCW, FNSTSW, FSTSW
- FINCSTP, FDECSTP, FFREE

**Special:**
- NOP, LEAVE

**Directives:**
- DU8, DU16, DU32 (data bytes)
- BINFILE (embed binary files)
- LIST, NOLIST (listing control)
- USE16, USE32, USE64 (mode directives)

**Type Prefixes for Memory Operands:**
- U64, I64, F64 (8 bytes)
- U32, I32 (4 bytes)
- U16, I16 (2 bytes)
- U8, I8 (1 byte)

Examples:
```asm
MOV RAX, I64 [RBP-8]    // Load 64-bit signed integer
FILD I32 [RBP-4]        // Load 32-bit integer to FPU
MOV AL, U8 [RSI]        // Load unsigned byte
```

## In Progress / TODO

### High Priority
- 🔄 Complete assembler parser (memory operands for all instructions)
- 🔄 Multi-pass assembly (forward label resolution)
- 🔄 Test hcas with generated assembly from hcc

### Medium Priority
- ⏳ Implement missing arithmetic/logical instruction encodings
- ⏳ Add support for more x64 instructions (IMUL multi-operand, LEA, etc.)
- ⏳ Improve memory operand parser (SIB byte, complex addressing)

### Low Priority
- ⏳ Add standalone test suite for hcpp
- ⏳ String literal / data section refactor
- ⏳ Print function implementation

### NOT Supported (TempleOS Limitations)
- ❌ `F32` type - TempleOS has F64 only
- ❌ `continue` keyword - use different loop structures
- ❌ `#undef` directive - not in TempleOS
- ❌ `#pragma` directive - not in TempleOS

## Known Issues / Limitations

- String literals not yet implemented (data section refactor needed)
- `print` function is stubbed (TODO: implement proper printf-style formatting)
- Limited instruction set coverage for less common x64 operations
- No SSE/SIMD support (x87 FPU only, TempleOS-compatible)
- Multi-pass label resolution in assembler is complete

## Reference Paths

**TempleOS Source:**
- `/home/admin/Downloads/TempleOS-archive/` - Reference for syntax and behavior
- `/home/admin/Downloads/TempleOS-archive/Once.HC` - Example of top-level execution
- `/home/admin/Downloads/TempleOS-archive/StartOS.HC` - Example of bare call syntax

**Active Development:**
- `/home/admin/Documents/GitHub/HolyCross/` - This repository

## Resources

- Zig 0.16 docs: https://ziglang.org/documentation/0.16.0/
- x64 instruction reference: https://www.felixcloutier.com/x86/
- System V AMD64 ABI: https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf
- TempleOS source: https://github.com/cia-foundation/TempleOS

## Contact / Feedback

Report issues: https://github.com/anomalyco/opencode

---

**Last Updated**: Phase 2 (Assembler implementation in progress)  
**Zig Version**: 0.16.0  
**Status**: Active development
