# HolyCross Compiler Architecture

This document provides an overview of the HolyCross compiler architecture and codebase organization.

## Overview

HolyCross is a compiler for the HolyC programming language (from TempleOS), targeting x64 Linux. The compiler follows a traditional multi-phase architecture:

```
Source Code
    ↓
[Preprocessor] → Handles #define, #ifdef, #include, etc.
    ↓
[Lexer] → Tokenizes source into tokens
    ↓
[Parser] → Builds Abstract Syntax Tree (AST)
    ↓
[Semantic Analyzer] → Type checking and symbol resolution
    ↓
[IR Builder] → Generates intermediate representation
    ↓
[Code Generator] → Produces x64 assembly
    ↓
[Assembler (gcc)] → Links and creates executable
    ↓
Executable
```

## Directory Structure

```
src/
├── main.zig                 # CLI entry point
├── preprocessor/            # Preprocessor implementation
│   ├── preprocessor.zig     # Main preprocessor logic
│   └── interpreter.zig      # #exe directive interpreter
├── lexer/                   # Lexical analysis
│   ├── lexer.zig           # Main lexer
│   ├── token.zig           # Token types and definitions
│   ├── keywords.zig        # Keyword recognition
│   ├── helpers.zig         # Character classification helpers
│   └── tests/              # Lexer tests
├── parser/                  # Syntax analysis
│   ├── parser.zig          # Recursive descent parser (1900+ lines)
│   ├── ast.zig             # AST node definitions
│   ├── precedence.zig      # Operator precedence tables
│   └── tests/              # Parser tests
├── semantic/                # Semantic analysis
│   ├── analyzer.zig        # Main semantic analyzer (1000+ lines)
│   ├── type_checker.zig    # Type inference and checking
│   ├── symbol_table.zig    # Symbol table management
│   ├── type_layout.zig     # Type size/alignment calculations
│   └── tests/              # Semantic analysis tests
├── codegen/                 # Code generation
│   ├── compiler.zig        # Compilation orchestration
│   ├── ir.zig              # IR node definitions
│   ├── ir_builder.zig      # AST → IR translation (1300+ lines)
│   ├── x64.zig             # x64 code generation
│   ├── x64/                # x64-specific modules
│   │   ├── instruction_gen.zig  # Instruction emission
│   │   ├── helpers.zig          # Register/memory helpers
│   │   └── control_flow.zig     # Control flow generation
│   └── tests/              # Codegen tests
└── assembler/               # Inline assembly support
    ├── assembler.zig       # Architecture-independent interface
    ├── x64.zig             # x64 assembler implementation
    └── tests/              # Assembler tests

examples/                    # Example HolyC programs
tests/                       # Integration tests
```

## Module Responsibilities

### Preprocessor (`src/preprocessor/`)

**Purpose**: Process preprocessor directives before compilation

**Key Features**:
- `#define` macro definitions
- `#ifdef`, `#ifndef`, `#else`, `#endif` conditional compilation
- `#include` file inclusion
- `#ifaot`, `#ifjit` compilation mode detection
- `#exe` compile-time code execution (WIP)

**Entry Point**: `Preprocessor.process(source) -> processed_source`

### Lexer (`src/lexer/`)

**Purpose**: Convert source text into stream of tokens

**Key Components**:
- **lexer.zig**: Main tokenization logic
- **token.zig**: Token type definitions (150+ token types)
- **keywords.zig**: Keyword recognition table
- **helpers.zig**: Character classification utilities

**Token Types**:
- Literals: integers, floats, strings, characters
- Keywords: type keywords (I64, U8, etc.), control flow, etc.
- Operators: arithmetic, logical, bitwise, assignment
- Delimiters: parentheses, braces, brackets, semicolons

**Entry Point**: `Lexer.nextToken() -> Token`

### Parser (`src/parser/`)

**Purpose**: Build Abstract Syntax Tree from tokens

**Architecture**:
- **Recursive descent** for statements and declarations
- **Pratt parsing** for expressions with proper precedence
- **Single-pass** with one-token lookahead

**Key Sections** (parser.zig):
- Token Management (lines 110-146)
- Error Handling & Recovery (lines 149-195)
- Declaration Parsing (lines 197-600): Functions, classes, unions, globals
- Expression Parsing (lines 600-1100): Binary, unary, literals, calls
- Type Parsing (lines 1100-1200): Primitives, pointers, arrays
- Statement Parsing (lines 1200-1700): Control flow, declarations

**AST Nodes** (ast.zig):
- `Decl`: Top-level declarations (functions, globals, classes)
- `Stmt`: Statements (if, while, for, return, blocks, etc.)
- `Expr`: Expressions (binary ops, calls, literals, etc.)
- `Type`: Type annotations (primitives, pointers, arrays, named)

**Entry Point**: `Parser.parse() -> Program`

### Semantic Analyzer (`src/semantic/`)

**Purpose**: Validate program semantics and build symbol table

**Key Components**:
- **analyzer.zig**: Main analysis orchestration
- **type_checker.zig**: Type inference and compatibility
- **symbol_table.zig**: Scoped symbol tracking
- **type_layout.zig**: Calculate sizes and offsets

**Responsibilities**:
- Symbol resolution (check all identifiers are declared)
- Type checking (validate type compatibility)
- Control flow validation (break/return in valid contexts)
- Class member resolution
- Function signature validation

**Entry Point**: `Analyzer.analyze(program) -> !void`

### IR Builder (`src/codegen/ir_builder.zig`)

**Purpose**: Translate AST into architecture-independent IR

**IR Design**:
- **Three-address code** format
- **SSA-like** with virtual registers (temporaries)
- **Basic blocks** with explicit control flow
- **Simple instruction set**: load, store, binary_op, call, return, etc.

**Translation Phases**:
1. Collect global variables and function signatures
2. For each function:
   - Build local variable table
   - Translate statements to IR instructions
   - Allocate temporaries for expression results
3. Emit IR module

**Entry Point**: `IRBuilder.buildFromAST(program) -> IRModule`

### Code Generator (`src/codegen/`)

**Purpose**: Generate x64 assembly from IR

**Architecture**:
- **IR → Assembly** translation
- **Register allocation**: Simple strategy using stack spills
- **Calling convention**: System V AMD64 ABI
- **Frame layout**: RBP-based stack frames

**Key Files**:
- **x64.zig**: Main code generation orchestration
- **instruction_gen.zig**: Emit x64 instructions
- **helpers.zig**: Register and memory operand helpers
- **control_flow.zig**: Branch and label generation

**Output Format**: Intel syntax AT&T assembly (`.s` file)

**Entry Point**: `X64Generator.generateFromIR(module) -> assembly_text`

### Assembler (`src/assembler/`)

**Purpose**: Support inline assembly in `asm { }` blocks

**Architecture**:
- **Architecture-independent interface**
- **x64 implementation**: Parse and encode x64 assembly
- **Raw assembly model**: No compiler integration (TempleOS-style)

**Supported Instructions**:
- MOV (register/immediate)
- PUSH/POP
- NOP
- Extensible architecture for adding more

**Entry Point**: `X64Assembler.parse(text)` and `.encode(instructions)`

## Data Flow Example

Here's how code flows through the compiler:

```c
// Source: hello.hc
I64 main() {
    I64 x = 42;
    return x;
}
```

**After Preprocessor**: (unchanged, no directives)

**After Lexer**: 
```
[I64] [identifier:"main"] [(] [)] [{]
[I64] [identifier:"x"] [=] [integer:42] [;]
[return] [identifier:"x"] [;]
[}]
```

**After Parser** (AST):
```
Program
└─ Decl::function "main"
   └─ Stmt::block
      ├─ Stmt::var_decl (type: I64, name: "x", init: 42)
      └─ Stmt::return (expr: identifier "x")
```

**After Semantic Analysis**:
- Symbol table: { "main" → Function, "x" → I64 local }
- Type check: "x" is I64, return type matches

**After IR Builder**:
```
function main:
  block0:
    %t0 = const 42
    store x, %t0
    %t1 = load x
    return %t1
```

**After Code Generator** (x64 assembly):
```asm
main:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    mov rax, 42
    mov [rbp-8], rax
    mov rax, [rbp-8]
    mov rsp, rbp
    pop rbp
    ret
```

## Design Principles

### 1. **Phased Architecture**
Each phase has clear inputs/outputs and responsibilities. This makes testing easier and allows for future optimizations between phases.

### 2. **Immutable AST**
The AST is built once and never modified. Each phase reads from previous phases without mutation.

### 3. **Arena Allocation**
The AST uses arena allocation - all nodes are allocated from a single arena and freed at once when done.

### 4. **Error Recovery**
The parser attempts to recover from errors and continue parsing to report multiple errors at once.

### 5. **Simplicity Over Optimization**
The compiler prioritizes correctness and simplicity over performance. Optimization opportunities are documented as TODOs.

## Key Design Decisions

### Why Recursive Descent + Pratt Parsing?
- **Recursive descent**: Natural mapping to grammar, easy to understand and maintain
- **Pratt parsing**: Handles operator precedence elegantly without complex grammar rules

### Why Three-Address IR?
- Simple and well-understood
- Easy to generate from AST
- Straightforward translation to assembly
- Good foundation for future optimizations

### Why Not SSA?
SSA (Static Single Assignment) would enable better optimizations but adds complexity. Current design can evolve to SSA if needed.

### Why Stack-Based Register Allocation?
The current approach spills everything to stack. This is simple and correct, though inefficient. A proper register allocator can be added later.

## Future Enhancements

### Short Term
- [ ] Complete inline assembly integration
- [ ] Add more x64 instructions
- [ ] Improve error messages with better source locations
- [ ] Add optimization flags

### Medium Term
- [ ] Register allocation optimization
- [ ] Common subexpression elimination
- [ ] Dead code elimination
- [ ] Constant folding

### Long Term
- [ ] SSA-based IR
- [ ] Multiple optimization passes
- [ ] ARM64 backend
- [ ] LLVM backend option
- [ ] Incremental compilation
- [ ] Debug info generation (DWARF)

## Testing Strategy

### Unit Tests
- Each module has its own test file in `tests/` subdirectory
- Test individual functions and edge cases
- Run with `zig build test`

### Integration Tests
- End-to-end compilation tests in `tests/`
- Compile and execute example programs
- Verify expected output/return codes

### Example Programs
- `examples/` directory contains working HolyC programs
- Used for manual testing and demonstration
- Good source of regression tests

## Performance Considerations

### Current Performance
The compiler is **not optimized** for speed. Priorities are:
1. Correctness
2. Maintainability  
3. Completeness
4. Performance

### Known Bottlenecks
- No intermediate caching
- Linear symbol table lookups
- Naive register allocation
- Single-threaded compilation

### When to Optimize
Optimize when:
- Compile times become painful for large projects
- Profiling shows clear hotspots
- Optimization doesn't compromise readability

## Contributing Guidelines

### Adding a New Feature

1. **Update AST** if needed (`parser/ast.zig`)
2. **Update Parser** to recognize new syntax
3. **Update Semantic Analyzer** for validation
4. **Update IR Builder** for translation
5. **Update Code Generator** for x64 emission
6. **Add Tests** at each level
7. **Update Documentation** (this file and module docs)

### Code Style
- Follow existing Zig conventions
- Use meaningful names
- Add comments for complex logic
- Keep functions focused and small
- Prefer clarity over cleverness

### Testing
- Write tests before implementing
- Test edge cases and error conditions
- Ensure tests pass before committing

## Resources

- **TempleOS Archive**: Reference for HolyC language design
- **Zig Documentation**: https://ziglang.org/documentation/
- **x64 Reference**: Intel® 64 and IA-32 Architectures Software Developer's Manuals
- **System V ABI**: Calling convention specification

## Questions?

For questions about the architecture or codebase, see:
- Module-level documentation (top of each `.zig` file)
- Inline comments for complex functions
- Git history for context on changes
- Test files for usage examples
