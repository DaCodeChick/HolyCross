# HolyC Cross-Compiler Project Plan

## Project Vision

A modern, cross-platform HolyC compiler written in Zig that enables developers to write TempleOS software from established development environments (Linux, Windows, macOS). The compiler will target TempleOS's native .BIN format while supporting native compilation for rapid development iteration.

### Core Philosophy
- **Bootstrap-first**: Zig-based compiler that remains in Zig
- **Native development**: Linux x64 ELF for rapid iteration
- **Cross-compilation**: Gradually add TempleOS .BIN output
- **Incremental learning**: Build understanding through implementation
- **Eventual capability**: Mature enough to enable HolyC-in-HolyC compiler if desired

## Project Goals

### Primary Goals
1. Compile HolyC source code to working binaries
2. Support native Linux x64 execution for development speed
3. Generate TempleOS-compatible .BIN executables
4. Handle core HolyC language features (classes, inline assembly, #exe directive)
5. Enable compilation of significant TempleOS applications

### Stretch Goals
1. Compile the original TempleOS compiler source code
2. Full x64 assembler (beyond HolyC inline assembly needs)
3. Self-hosting capability (compiler written in HolyC)
4. Additional architecture targets (ARM, RISC-V)
5. Modern tooling (LSP, debugger integration)

## Technical Architecture

### High-Level Overview
```
┌─────────────────────────────────────────────┐
│  HolyC Cross-Compiler (Zig)                 │
├─────────────────────────────────────────────┤
│                                             │
│  Frontend                                   │
│    ├─ Lexer                                 │
│    ├─ Preprocessor (#include, #define)      │
│    ├─ Parser (Recursive Descent)            │
│    └─ Semantic Analysis                     │
│                                             │
│  Middle-End                                 │
│    ├─ AST (Abstract Syntax Tree)            │
│    ├─ IR (Intermediate Representation)      │
│    ├─ Symbol Tables                         │
│    └─ Type Resolution                       │
│                                             │
│  Backend                                    │
│    ├─ Code Generation                       │
│    ├─ Register Allocation                   │
│    ├─ Instruction Emission                  │
│    ├─ Inline Assembly Handler               │
│    └─ Binary Format Writers                 │
│        ├─ ELF (Linux x64)                   │
│        └─ BIN (TempleOS)                    │
│                                             │
│  Runtime Support                            │
│    ├─ TempleOS stdlib stubs                 │
│    ├─ Linux runtime shim                    │
│    └─ Minimal libc interface                │
└─────────────────────────────────────────────┘
```

### Component Breakdown

#### 1. Lexer
- **Purpose**: Tokenize HolyC source into token stream
- **Input**: Raw source text (.HC files)
- **Output**: Token stream
- **Features**:
  - Keywords (89 HolyC keywords)
  - Operators (including HolyC-specific like ` for power)
  - Literals (multi-character constants: 'Hello')
  - Comments (// and /* */)
  - DolDoc format awareness (optional, later phase)

#### 2. Preprocessor
- **Purpose**: Handle compile-time directives
- **Features**:
  - `#include` - File inclusion
  - `#define` - Macro definitions
  - `#exe` - Compile-time code execution (advanced feature)
  - `#ifdef/#ifndef` - Conditional compilation
  - Macro expansion

#### 3. Parser
- **Purpose**: Build Abstract Syntax Tree from tokens
- **Algorithm**: Recursive descent with operator precedence
- **Features**:
  - Expression parsing (including chained comparisons: `5 < x < 10`)
  - Statement parsing (if/while/for/switch/try/catch)
  - Function definitions
  - Class/struct declarations (single inheritance)
  - Inline assembly blocks (`asm {}`)

#### 4. Semantic Analysis
- **Purpose**: Type checking and symbol resolution
- **Features**:
  - Symbol table management
  - Type resolution (loose, HolyC is weakly typed)
  - Class inheritance resolution
  - Function signature checking
  - Variable scope tracking

#### 5. Intermediate Representation (IR)
- **Purpose**: Platform-independent code representation
- **Design**: Custom IR inspired by TempleOS's IC_* codes
- **Features**:
  - SSA form (optional, for optimization)
  - Type annotations
  - Control flow graph
  - Register hints (for inline assembly integration)

#### 6. Code Generation
- **Purpose**: Emit machine code from IR
- **Targets**:
  - **Phase 1**: x64 Linux (System V ABI)
  - **Phase 2**: x64 TempleOS (custom ABI, ring 0, flat memory)
- **Features**:
  - Instruction selection
  - Register allocation (graph coloring or linear scan)
  - Stack frame management
  - Calling convention handling

#### 7. Inline Assembly Handler
- **Purpose**: Parse and emit inline `asm {}` blocks
- **Scope**: Start with common TempleOS patterns, expand to full x64
- **Features**:
  - x64 instruction parsing
  - ModR/M and SIB byte encoding
  - Register allocation coordination
  - Label resolution
  - Access to HolyC variables from assembly

#### 8. Binary Format Writers
- **ELF Writer** (Linux x64):
  - Standard ELF64 format
  - .text, .data, .bss sections
  - Symbol table, relocation entries
  - Dynamic linking to libc (for printf, malloc stubs)

- **BIN Writer** (TempleOS):
  - 'TOSB' magic number (0x54_4F_53_42 big-endian)
  - Custom header structure (reverse-engineered)
  - Flat memory model
  - Symbol table for TempleOS loader
  - No sections (flat binary with metadata)

## Implementation Phases

### Phase 0: Foundation (Weeks 1-2)
**Goal**: Project infrastructure and basic lexer

**Deliverables**:
- [x] Git repository structure
- [x] Zig build system configured
- [x] Project documentation (PLAN.md)
- [ ] Basic lexer (tokenization only)
- [ ] Token types defined
- [ ] Simple test harness

**Learning Focus**:
- Zig build system
- Lexical analysis fundamentals
- Token design patterns

**Tests**:
```holyc
// Test file: basic_tokens.hc
I64 x = 42;
U0 Main() {}
```
Expected output: Token stream with correct types

---

### Phase 1: Expression Evaluator (Weeks 3-4)
**Goal**: Parse and evaluate arithmetic expressions

**Deliverables**:
- [ ] Expression parser (recursive descent)
- [ ] Operator precedence handling
- [ ] Basic AST nodes (BinaryOp, Literal, etc.)
- [ ] Simple interpreter for expressions

**Learning Focus**:
- Recursive descent parsing
- Operator precedence
- AST design
- Pratt parsing (optional)

**Tests**:
```holyc
2 + 3 * 4        // Should evaluate to 14
5 << 2 + 1       // Should evaluate to 40
10 / 2 - 3       // Should evaluate to 2
```

---

### Phase 2: Hello World (Native Linux) (Weeks 5-8)
**Goal**: Compile and run simple HolyC program on Linux

**Deliverables**:
- [ ] Function definition parsing
- [ ] Statement parser (basic)
- [ ] x64 code generation (minimal)
- [ ] ELF binary writer
- [ ] Linux syscall integration (write)
- [ ] String literal handling

**Learning Focus**:
- x64 assembly basics
- Linux System V ABI calling convention
- Stack frames and prologue/epilogue
- ELF binary format
- Syscalls vs libc

**Tests**:
```holyc
// hello.hc
U0 Main() {
    "Hello, World!\n";
}
```
Compile: `./holycc hello.hc -o hello`
Run: `./hello` → outputs "Hello, World!"

**Technical Details**:
- `"string"` implicitly calls `Print()` in HolyC
- For Linux, map to `write(1, str, len)` syscall
- Generate:
  ```asm
  ; Simplified
  mov rax, 1          ; sys_write
  mov rdi, 1          ; stdout
  lea rsi, [msg]      ; buffer
  mov rdx, 14         ; length
  syscall
  ```

---

### Phase 3: Variables and Types (Weeks 9-12)
**Goal**: Support HolyC type system and variables

**Deliverables**:
- [ ] Variable declarations (I64, U8, F64, etc.)
- [ ] Type system implementation
- [ ] Memory allocation (stack-based)
- [ ] Assignment statements
- [ ] Type casting (postfix: `x(U8*)`)
- [ ] Pointer basics

**Learning Focus**:
- Type systems (weak typing)
- Memory layout and alignment
- Pointer arithmetic
- x64 addressing modes

**Tests**:
```holyc
U0 Main() {
    I64 x = 42;
    U8 y = 100;
    F64 pi = 3.14159;
    
    x = x + 10;
    "x = %d\n", x;  // Should print 52
}
```

---

### Phase 4: Control Flow (Weeks 13-16)
**Goal**: Implement branching and loops

**Deliverables**:
- [ ] if/else statements
- [ ] while loops
- [ ] for loops
- [ ] switch statements (basic)
- [ ] Conditional jumps in codegen
- [ ] Label management

**Learning Focus**:
- Control flow graphs
- Jump instructions (JMP, JE, JNE, etc.)
- Label resolution
- Short vs near jumps

**Tests**:
```holyc
U0 Main() {
    I64 i;
    for (i = 0; i < 10; i++) {
        if (i % 2 == 0)
            "Even: %d\n", i;
        else
            "Odd: %d\n", i;
    }
}
```

---

### Phase 5: Functions (Weeks 17-20)
**Goal**: Function calls and returns

**Deliverables**:
- [ ] Function declarations and definitions
- [ ] Parameter passing
- [ ] Return values
- [ ] Local variable scoping
- [ ] Calling convention implementation
- [ ] Function pointers (basic)

**Learning Focus**:
- x64 calling conventions (System V)
- Stack frame layout
- Register preservation (caller/callee saved)
- Return value passing

**Tests**:
```holyc
I64 Add(I64 a, I64 b) {
    return a + b;
}

U0 Main() {
    I64 result = Add(5, 7);
    "Result: %d\n", result;
}
```

---

### Phase 6: Structs and Classes (Weeks 21-26)
**Goal**: HolyC class system (single inheritance)

**Deliverables**:
- [ ] Struct definitions
- [ ] Class definitions
- [ ] Single inheritance support
- [ ] Member access (dot operator)
- [ ] Pointer member access (->)
- [ ] Member offset calculation
- [ ] Size calculation with inheritance

**Learning Focus**:
- Memory layout for structs
- Inheritance (field concatenation)
- Alignment and padding
- Type composition

**Tests**:
```holyc
class Point {
    I64 x;
    I64 y;
};

class Point3D : Point {
    I64 z;
};

U0 Main() {
    Point3D p;
    p.x = 10;
    p.y = 20;
    p.z = 30;
    "Point: (%d, %d, %d)\n", p.x, p.y, p.z;
}
```

---

### Phase 7: Pointers and Arrays (Weeks 27-30)
**Goal**: Full pointer and array support

**Deliverables**:
- [ ] Pointer arithmetic
- [ ] Array indexing
- [ ] Multidimensional arrays
- [ ] Pointer to pointer
- [ ] Address-of (&) operator
- [ ] Dereference (*) operator

**Learning Focus**:
- Pointer semantics
- Array decay to pointer
- Memory addressing calculations
- x64 addressing modes (displacement, base+index)

**Tests**:
```holyc
U0 Main() {
    I64 arr[10];
    I64 i;
    
    for (i = 0; i < 10; i++)
        arr[i] = i * i;
    
    I64 *ptr = arr;
    "First: %d, Second: %d\n", ptr[0], ptr[1];
}
```

---

### Phase 8: TempleOS Binary Format (Weeks 31-36)
**Goal**: Generate TempleOS-compatible .BIN files

**Deliverables**:
- [ ] Reverse-engineer .BIN format from TempleOS source
- [ ] Implement BIN file writer
- [ ] 'TOSB' magic number header
- [ ] Symbol table generation
- [ ] Relocation handling
- [ ] Test in TempleOS VM (milestone validation)

**Learning Focus**:
- Binary file formats
- Executable loaders
- Symbol resolution
- TempleOS-specific conventions

**Tests**:
```holyc
// Compile to .BIN, test in TempleOS VM
U0 Main() {
    "Hello from cross-compiled binary!\n";
}
```

**Reverse Engineering Approach**:
1. Study `Kernel/KLoad.HC` (binary loader)
2. Analyze existing .BIN files with hex editor
3. Compare with compiler output in `Compiler/BackA.HC`
4. Document structure in `docs/bin_format.md`

---

### Phase 9: TempleOS Runtime Integration (Weeks 37-42)
**Goal**: Interface with TempleOS standard library

**Deliverables**:
- [ ] TempleOS calling convention
- [ ] Standard library function stubs
- [ ] Print(), PutChars() integration
- [ ] MAlloc(), Free() memory management
- [ ] Exception handling basics (try/catch)

**Learning Focus**:
- TempleOS ABI
- Ring 0 execution model
- Flat memory model (no virtual memory)
- TempleOS task structure (CTask)

**Tests**:
```holyc
// Uses TempleOS stdlib
U0 Main() {
    I64 *ptr = MAlloc(sizeof(I64) * 10);
    I64 i;
    
    for (i = 0; i < 10; i++)
        ptr[i] = i;
    
    "Array created at %X\n", ptr;
    Free(ptr);
}
```

---

### Phase 10: Inline Assembly (Weeks 43-50)
**Goal**: Support HolyC's inline assembly blocks

**Deliverables**:
- [ ] Assembly block parser (`asm {}`)
- [ ] x64 instruction parser
- [ ] Common instruction encodings (MOV, ADD, CALL, JMP, etc.)
- [ ] Register access from HolyC variables
- [ ] ModR/M and SIB byte generation
- [ ] Label resolution within asm blocks

**Learning Focus**:
- x64 instruction encoding
- Opcode tables
- ModR/M byte structure
- SIB byte structure
- REX prefixes (64-bit mode)

**Tests**:
```holyc
U0 TestAsm() {
    I64 x = 42;
    I64 result;
    
    asm {
        MOV RAX, x
        ADD RAX, 10
        MOV result, RAX
    }
    
    "Result: %d\n", result;  // Should print 52
}
```

**Instruction Encoding Example**:
```
MOV RAX, [RBP-8]  ; Load x from stack
; Encoding: 48 8B 45 F8
;   48 = REX.W prefix (64-bit operand)
;   8B = MOV opcode (r64, r/m64)
;   45 = ModR/M: MOD=01 (disp8), REG=000 (RAX), R/M=101 (RBP)
;   F8 = Displacement (-8)
```

---

### Phase 11: Preprocessor Advanced (Weeks 51-56)
**Goal**: Full preprocessor with #exe directive

**Deliverables**:
- [ ] Macro expansion
- [ ] Conditional compilation (#ifdef, #ifndef)
- [ ] File inclusion (#include)
- [ ] #exe directive (compile-time execution)
- [ ] Nested compilation contexts

**Learning Focus**:
- Macro hygiene
- Compile-time execution
- Interpreter design (for #exe)
- Meta-programming

**Tests**:
```holyc
#define SQUARE(x) ((x) * (x))

#exe {
    I64 i;
    for (i = 0; i < 5; i++)
        StreamPrint("I64 var%d = %d;\n", i, i * 10);
}
// Above generates:
// I64 var0 = 0;
// I64 var1 = 10;
// I64 var2 = 20;
// ...

U0 Main() {
    I64 x = SQUARE(5);
    "x = %d\n", x;  // 25
    "var2 = %d\n", var2;  // 20
}
```

**#exe Implementation Strategy**:
- Parse #exe block as normal HolyC
- Option 1: Interpret the block (simpler)
- Option 2: JIT compile and execute (complex)
- Capture stdout/StreamPrint output
- Inject output back into token stream

---

### Phase 12: Optimization (Weeks 57-64)
**Goal**: Basic optimization passes

**Deliverables**:
- [ ] Constant folding
- [ ] Dead code elimination
- [ ] Common subexpression elimination
- [ ] Register allocation (graph coloring)
- [ ] Peephole optimization

**Learning Focus**:
- Optimization theory
- Data flow analysis
- Register allocation algorithms
- Trade-offs (compile time vs runtime)

**Tests**:
```holyc
// Before optimization
U0 Main() {
    I64 x = 5 + 3;      // Should fold to 8
    I64 y = x * 2;
    I64 z = x * 2;      // Common subexpression
    
    if (0) {            // Dead code
        "Never printed\n";
    }
}

// After optimization: dead code removed, constants folded, CSE applied
```

---

### Phase 13: Standard Library Stubs (Weeks 65-72)
**Goal**: Implement commonly-used TempleOS stdlib functions

**Deliverables**:
- [ ] String functions (StrCpy, StrCmp, StrLen, etc.)
- [ ] Memory functions (MemCpy, MemSet, MemCmp)
- [ ] Math functions (Sin, Cos, Sqrt, etc.)
- [ ] File I/O stubs (FOpen, FClose, FRead, FWrite)
- [ ] Print formatting (Print with %-specifiers)

**Learning Focus**:
- Runtime library design
- Calling external functions
- Variadic functions (argc/argv)

**Tests**:
```holyc
U0 Main() {
    U8 *str1 = "Hello";
    U8 *str2 = StrNew(str1);  // Allocate and copy
    
    "Original: %s\n", str1;
    "Copy: %s\n", str2;
    
    Free(str2);
}
```

---

### Phase 14: Advanced HolyC Features (Weeks 73-84)
**Goal**: Implement remaining HolyC-specific features

**Deliverables**:
- [ ] Chained comparisons (`5 < x < 10`)
- [ ] No-parentheses function calls (`MyFunc;`)
- [ ] Multi-character constants (`'Hello'`)
- [ ] Sub-switch statements
- [ ] Case ranges (`case 4...7:`)
- [ ] Default function arguments
- [ ] Class member metadata
- [ ] Union types (HolyC-style)

**Learning Focus**:
- Language quirks and special cases
- Edge case handling
- Backward compatibility

**Tests**:
```holyc
U0 PrintRange(I64 min, I64 max) {
    I64 i;
    for (i = min; i < max; i++) {
        switch (i) {
            case 0...3:
                "Low: %d\n", i;
                break;
            case 4...7:
                "Mid: %d\n", i;
                break;
            default:
                "High: %d\n", i;
        }
    }
}

U0 Main() {
    if (5 < 10 < 15)  // Chained comparison
        "Chained comparison works!\n";
    
    PrintRange(0, 10);
}
```

---

### Phase 15: Real-World Testing (Weeks 85-96)
**Goal**: Compile significant TempleOS applications

**Deliverables**:
- [ ] Compile TempleOS utilities (Dir, Copy, etc.)
- [ ] Compile demos from Demo/ directory
- [ ] Compile games (simple ones)
- [ ] Bug fixes from real-world code
- [ ] Performance profiling and improvements

**Testing Targets**:
1. Simple utilities (~100 lines)
2. Medium applications (~500 lines)
3. Graphics demos (~1000 lines)
4. Complex applications (2000+ lines)

**Success Criteria**:
- Binaries run correctly on TempleOS VM
- Output matches original compiler
- Performance acceptable (no need to match JIT speed)

---

### Phase 16: TempleOS Compiler Compilation (Weeks 97-120+)
**Goal**: Compile the TempleOS compiler itself

**Deliverables**:
- [ ] Compile `Compiler/CMain.HC` and dependencies
- [ ] Handle all advanced compiler features
- [ ] Fix bugs discovered during compilation
- [ ] Generate working compiler binary
- [ ] Test: compiled compiler can compile Hello World

**Challenges**:
- Compiler uses all advanced HolyC features
- Self-referential code
- Meta-programming (#exe blocks)
- Inline assembly throughout
- ~10,000 lines of complex code

**Success Criteria**:
- `./holycc Compiler/CMain.HC -o holyc_native.bin`
- Run on TempleOS: `holyc_native.bin HelloWorld.HC`
- Successfully compiles and runs Hello World

This is the ultimate test of compiler completeness.

---

### Phase 17: Full x64 Assembler (Optional Stretch Goal)
**Goal**: Expand inline assembly to full assembler

**Deliverables**:
- [ ] Standalone assembler tool
- [ ] All x64 instructions (SSE, AVX, etc.)
- [ ] Macro system
- [ ] Multiple output formats
- [ ] Assembler directives (.data, .text, etc.)

**Learning Focus**:
- Complete x64 instruction set
- SIMD instructions
- Assembler design patterns

---

### Phase 18: Additional Architectures (Optional Stretch Goal)
**Goal**: Support non-x64 targets

**Potential Targets**:
- ARM64 (aarch64)
- RISC-V (rv64)
- WebAssembly (for web demos)

**Challenges**:
- TempleOS is x64-only, so this would be for non-TempleOS targets
- Inline assembly would need architecture translation
- Different calling conventions

---

## Technical Challenges and Solutions

### Challenge 1: Chained Comparisons
**Problem**: HolyC allows `5 < x < 10` instead of `5 < x && x < 10`

**Solution**:
- Parse comparisons specially
- Transform during parsing or IR generation:
  ```
  5 < x < 10  →  (5 < x) && (x < 10)
  ```
- Track intermediate values to avoid double evaluation:
  ```zig
  // Pseudocode
  temp = x;
  result = (5 < temp) && (temp < 10);
  ```

### Challenge 2: #exe Directive
**Problem**: Execute HolyC code at compile time, output becomes source

**Solution** (Interpreter Approach):
1. Parse #exe block as normal HolyC AST
2. Build simple HolyC interpreter (subset of features needed)
3. Provide `StreamPrint()` function that captures to buffer
4. Execute interpreted code
5. Inject buffer contents into lexer stream

**Solution** (JIT Approach - more complex):
1. Compile #exe block to native code
2. Load into memory (dlopen/mmap)
3. Execute with stdout redirected
4. Capture output, inject into lexer

**Recommendation**: Start with interpreter, add JIT later if needed.

### Challenge 3: Inline Assembly Integration
**Problem**: Assembly blocks access HolyC variables, labels, functions

**Solution**:
- Track variable locations (stack offsets, registers)
- Pass symbol table to assembly parser
- Resolve HolyC identifiers in assembly context:
  ```holyc
  I64 x = 42;
  asm {
      MOV RAX, x  // Need to know x is at [RBP-8]
  }
  ```
- Transform to: `MOV RAX, [RBP-8]`
- Coordinate register allocation between HolyC and assembly

### Challenge 4: TempleOS Binary Format
**Problem**: Undocumented custom format

**Solution**:
1. Study TempleOS source:
   - `Kernel/KLoad.HC` - loader code
   - `Compiler/BackA.HC` - code generation
   - `Adam/Opt/Utils/BinDump.HC` - binary analysis tool
2. Analyze sample .BIN files with hex editor
3. Document structure:
   ```
   Offset  Size  Description
   0x00    4     'TOSB' magic (0x54_4F_53_42)
   0x04    4     Version/flags
   0x08    8     Entry point offset
   0x10    8     Code size
   0x18    8     Data size
   0x20    8     Symbol table offset
   ...
   ```
4. Implement writer incrementally, validate in VM

### Challenge 5: Weak Type System
**Problem**: HolyC is very loosely typed, allows implicit conversions

**Solution**:
- Implement permissive type checking
- Allow pointer/integer conversions freely
- Warn but don't error on suspicious conversions
- Trust the programmer (TempleOS philosophy)

### Challenge 6: No Standard Library Separation
**Problem**: TempleOS stdlib is tightly integrated with OS

**Solution**:
- For Linux: Create shim layer that maps TempleOS functions to libc
  ```c
  // tos_shim.c
  void Print(const char *fmt, ...) {
      va_list args;
      va_start(args, fmt);
      vprintf(fmt, args);
      va_end(args);
  }
  ```
- For TempleOS: Generate correct .BIN with external symbol references
- Link against TempleOS kernel at runtime

### Challenge 7: Ring 0 Execution Model
**Problem**: TempleOS runs everything in ring 0, no memory protection

**Solution**:
- For cross-compilation: This is handled by TempleOS OS, not compiler
- Generate correct code assuming flat memory model
- No segment registers, no privilege checks
- Direct hardware access allowed (for inline assembly)

## Testing Strategy

### Unit Tests
- **Lexer**: Token stream correctness
- **Parser**: AST structure validation
- **Codegen**: Instruction sequences
- **Binary format**: Header/section correctness

### Integration Tests
- **End-to-end**: Source → binary → execution
- **Feature tests**: Each language feature in isolation
- **Regression tests**: Previous bugs don't resurface

### Validation Tests (VM Milestones)
- **Phase 8**: First .BIN file runs on TempleOS
- **Phase 13**: Standard library usage
- **Phase 15**: Real TempleOS applications
- **Phase 16**: Compiler self-compilation

### Test Organization
```
tests/
├── unit/
│   ├── lexer_test.zig
│   ├── parser_test.zig
│   └── codegen_test.zig
├── integration/
│   ├── hello_world.hc
│   ├── fibonacci.hc
│   └── struct_test.hc
├── vm_validation/  (run manually in VirtualBox)
│   ├── basic.hc
│   ├── stdlib.hc
│   └── graphics.hc
└── regression/
    └── issue_001.hc
```

### Continuous Testing
- Native tests: Run on every commit
- VM tests: Run at milestones or weekly
- Automated where possible (scripted VM testing)

## Development Workflow

### Daily Development Loop
1. **Pick a task** from current phase
2. **Write test** for the feature (TDD approach)
3. **Implement** the feature
4. **Run tests** (native, fast iteration)
5. **Code review** (you audit my code)
6. **Commit** with descriptive message
7. **Document** learnings and challenges

### Milestone Validation
1. **Complete phase** deliverables
2. **Run full test suite** (native)
3. **Test in TempleOS VM** (for phases 8+)
4. **Document phase** in progress log
5. **Reflect**: What worked? What didn't?
6. **Plan next phase** adjustments

### Learning Integration
- **Before feature**: Read relevant theory/documentation
- **During implementation**: Learn by doing, experiment
- **After feature**: Document understanding, explain concepts
- **Code review**: You audit, ask questions, I explain

## Documentation Strategy

### Code Documentation
- **Every module**: Purpose, design decisions
- **Complex algorithms**: Inline comments explaining "why"
- **Public APIs**: Doc comments for all public functions
- **Examples**: Usage examples for major components

### Project Documentation
- **Architecture docs**: High-level design (this file)
- **Format specs**: Binary formats, ABIs (docs/bin_format.md)
- **Progress log**: Phase completion, blockers, learnings
- **How-to guides**: Building, testing, contributing

### Learning Documentation
- **Concept explanations**: x64 encoding, calling conventions, etc.
- **Decision rationale**: Why we chose X over Y
- **Resources**: Links to manuals, books, articles
- **Lessons learned**: Mistakes made, solutions found

## Repository Structure

```
holyc-compiler/
├── src/
│   ├── main.zig              # Entry point
│   ├── lexer/
│   │   ├── lexer.zig         # Lexer implementation
│   │   ├── token.zig         # Token types
│   │   └── lexer_test.zig    # Lexer tests
│   ├── parser/
│   │   ├── parser.zig        # Parser implementation
│   │   ├── ast.zig           # AST node definitions
│   │   └── parser_test.zig   # Parser tests
│   ├── semantic/
│   │   ├── analyzer.zig      # Semantic analysis
│   │   ├── symbol_table.zig  # Symbol management
│   │   └── types.zig         # Type system
│   ├── ir/
│   │   ├── ir.zig            # Intermediate representation
│   │   └── builder.zig       # IR construction
│   ├── codegen/
│   │   ├── codegen.zig       # Code generation interface
│   │   ├── x64/
│   │   │   ├── x64.zig       # x64 backend
│   │   │   ├── encoder.zig   # Instruction encoding
│   │   │   ├── registers.zig # Register allocation
│   │   │   └── abi.zig       # Calling conventions
│   │   └── asm/
│   │       ├── parser.zig    # Assembly parser
│   │       └── emitter.zig   # Asm code emission
│   ├── binary/
│   │   ├── elf.zig           # ELF writer
│   │   └── tosbin.zig        # TempleOS .BIN writer
│   ├── preprocessor/
│   │   ├── preprocessor.zig  # Preprocessor
│   │   └── macro.zig         # Macro expansion
│   └── runtime/
│       ├── tos_shim.c        # TempleOS stdlib shim (for Linux)
│       └── tos_stubs.hc      # Minimal TempleOS stubs
├── tests/
│   ├── unit/                 # Unit tests (Zig)
│   ├── integration/          # Integration tests (.hc files)
│   ├── vm_validation/        # TempleOS VM tests
│   └── regression/           # Regression tests
├── examples/
│   ├── hello.hc              # Hello World
│   ├── fibonacci.hc          # Fibonacci sequence
│   ├── structs.hc            # Struct usage
│   └── asm.hc                # Inline assembly
├── docs/
│   ├── PLAN.md               # This file
│   ├── architecture.md       # Detailed architecture
│   ├── bin_format.md         # TempleOS .BIN format spec
│   ├── holyc_reference.md    # HolyC language reference
│   ├── x64_reference.md      # x64 instruction encoding
│   └── progress.md           # Development progress log
├── tools/
│   └── vm_test.sh            # Script for VirtualBox testing
├── build.zig                 # Zig build configuration
├── build.zig.zon             # Zig dependencies
├── .gitignore                # Git ignore patterns
├── LICENSE                   # LGPL v3
└── README.md                 # Project README
```

## Tooling and Dependencies

### Build System
- **Zig build system**: Native, no external tools needed
- **Build modes**: Debug, ReleaseFast, ReleaseSmall
- **Cross-compilation**: Built into Zig

### Development Tools
- **Editor**: Any (VSCode with Zig extension recommended)
- **Debugger**: gdb/lldb for native debugging
- **Hex editor**: For binary format analysis (ghex, hexdump)
- **VM**: VirtualBox with TempleOS/ZealOS images

### External Dependencies
- **Minimal philosophy**: Avoid dependencies where possible
- **Standard library only**: Use Zig stdlib
- **No LLVM**: We're building from scratch
- **Optional**: Keystone/Capstone for assembly validation (testing only)

## Success Metrics

### Phase Completion
- All deliverables implemented
- Tests passing
- Documentation updated
- VM validation (for relevant phases)

### Code Quality
- Clean, readable code
- Well-documented
- No warnings in debug build
- Consistent style (zig fmt)

### Learning Outcomes
- Deep understanding of compilers
- x64 architecture mastery
- Binary format knowledge
- HolyC language expertise

### Long-term Goals
- Compile simple programs: **3 months**
- Compile complex programs: **12 months**
- Compile TempleOS compiler: **24+ months**
- Community adoption: **18+ months**

## Risk Management

### Technical Risks
1. **Complexity underestimation**: Phases take longer than planned
   - **Mitigation**: Break phases into smaller tasks, adjust timeline
2. **TempleOS format issues**: Can't reverse-engineer .BIN format
   - **Mitigation**: Engage ZealOS community, study multiple sources
3. **Inline assembly complexity**: Full x64 support overwhelming
   - **Mitigation**: Start with subset, expand incrementally
4. **#exe directive**: Compile-time execution too complex
   - **Mitigation**: Simplify (support subset), or defer to later phase

### Personal Risks
1. **Burnout**: Project is too ambitious
   - **Mitigation**: No deadlines, work at comfortable pace
2. **Loss of motivation**: Early phases feel tedious
   - **Mitigation**: Quick wins (Hello World early), celebrate milestones
3. **Scope creep**: Adding features not in plan
   - **Mitigation**: Document ideas for "Phase 2", stay focused on plan

## References and Resources

### HolyC and TempleOS
- TempleOS GitHub: https://github.com/cia-foundation/TempleOS
- ZealOS GitHub: https://github.com/Zeal-Operating-System/ZealOS
- Terry Davis's videos: YouTube (historical context)
- HolyC Charter: `Doc/Charter.DD` in TempleOS repo

### Compiler Theory
- **Books**:
  - "Engineering a Compiler" (Cooper & Torczon)
  - "Modern Compiler Implementation in C" (Appel)
  - "Crafting Interpreters" (Nystrom) - Free online
- **Online**:
  - Stanford CS143 (Compilers) lecture notes
  - LLVM documentation (for concepts, not usage)

### x64 Architecture
- **Intel Manuals**: Software Developer's Manual (SDM) Volumes 1-3
- **AMD Manuals**: AMD64 Architecture Programmer's Manual
- **Online**:
  - OSDev Wiki: x86-64 articles
  - Felix Cloutier's x86 reference: https://www.felixcloutier.com/x86/
  - "x86-64 Assembly Language Programming with Ubuntu" (Jorgensen)

### Binary Formats
- **ELF**: "Learning Linux Binary Analysis" (O'Neill)
- **ELF Spec**: Tool Interface Standard (TIS) ELF specification
- **TempleOS**: Reverse-engineer from source (Kernel/KLoad.HC)

### Zig Language
- **Official**: https://ziglang.org/documentation/master/
- **Zig Learn**: https://ziglearn.org/
- **Zig Guide**: Community guides and tutorials

## License

This project is licensed under **GNU Lesser General Public License v3.0 (LGPL-3.0)**.

### Rationale
- **Copyleft**: Ensures improvements remain open source
- **Library exception**: Allows linking with proprietary code (useful for compiler)
- **Community friendly**: Encourages contributions and forks
- **Compatible with GNU toolchain philosophy**

See LICENSE file for full text.

## Contributing (Future)

While currently a personal learning project, future contributions welcome:
- Bug reports
- Test cases (especially real TempleOS code)
- Documentation improvements
- Performance optimizations
- Additional architecture backends

## Acknowledgments

- **Terry A. Davis**: Creator of TempleOS and HolyC
- **Zeal OS Team**: Continued development and documentation
- **Zig Community**: Excellent language and tooling
- **Compiler theory researchers**: Decades of CS research

---

## Next Steps

1. **Set up repository**: Initialize Git, create directory structure
2. **Implement Phase 0**: Basic lexer and project infrastructure
3. **First milestone**: Tokenize simple HolyC file
4. **Begin learning journey**: Start with lexical analysis fundamentals

Let's build something amazing! 🎯

---

*Last Updated*: 2026-01-09
*Status*: Phase 0 - Foundation
*Progress*: 0% (Just beginning!)
