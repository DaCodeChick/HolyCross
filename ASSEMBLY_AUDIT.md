# HolyCross Assembly & Preprocessor Audit

**Date**: 2026-05-13  
**Purpose**: Audit current assembler and preprocessor implementations to plan extraction into standalone CLI tools

---

## Executive Summary

HolyCross currently has:
1. ✅ **Text Assembly Generator** (`src/codegen/x64.zig`) - Generates TempleOS-style assembly
2. ✅ **Assembler Framework** (`src/assembler/`) - Parser/encoder infrastructure (partial implementation)
3. ✅ **Preprocessor** (`src/preprocessor/`) - Full preprocessing with conditionals and includes
4. ⚠️ **Machine Code Generator** (`src/codegen/x64_machine_code.zig`) - Direct binary generation

**Goal**: Extract these into 3 standalone CLI tools:
- `hcpp` - Preprocessor
- `hcas` - Assembler  
- `hcc` - Compiler (orchestrates the above)

---

## 1. Preprocessor Analysis

### Location
- `src/preprocessor/preprocessor.zig` (506 lines)
- `src/preprocessor/interpreter.zig` (#exe support)

### Currently Supported Directives

| Directive | Status | Notes |
|-----------|--------|-------|
| `#define` | ✅ | Macro definitions |
| `#include` | ✅ | File inclusion with depth limits |
| `#ifdef` | ✅ | Conditional compilation |
| `#ifndef` | ✅ | Negative conditional |
| `#else` | ✅ | Conditional alternative |
| `#endif` | ✅ | End conditional block |
| `#ifaot` | ✅ | AOT compilation check |
| `#ifjit` | ✅ | JIT compilation check |
| `#exe` | ✅ | Compile-time execution |

### Missing TempleOS Directives

Based on TempleOS documentation:

| Directive | Priority | Notes |
|-----------|----------|-------|
| `#help_index` | Low | Documentation system |
| `#assert` | Medium | Compile-time assertions |
| `#if` | High | General expression evaluation |
| `#elif` | High | Chained conditionals |
| `#undef` | Medium | Remove macro definitions |
| `#pragma` | Low | Compiler hints |
| `#error` | Medium | User-defined errors |
| `#warning` | Low | User-defined warnings |

### Preprocessor Interface

**Current**: Embedded in compiler flow  
**Proposed**: Standalone tool

```bash
# Proposed CLI
hcpp input.HC -o output.i
hcpp input.HC -D DEBUG=1 -D VERSION=2 -o output.i
hcpp --include-dir /path/to/includes input.HC
```

**Required Changes**:
1. Extract preprocessor into `src/tools/hcpp.zig`
2. Add CLI argument parsing (defines, include paths, output)
3. Make preprocessor self-contained (no compiler dependencies)
4. Add standalone test suite

---

## 2. Assembler Analysis

### Location
- `src/assembler/assembler.zig` - Interface (175 lines)
- `src/assembler/x64.zig` - x64 implementation
- `src/codegen/x64.zig` - Assembly generator (462 lines)
- `src/codegen/x64/instruction_gen.zig` - Instruction emission (21KB)

### Current Assembly Syntax (TempleOS-Style)

#### Data Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `DU8` | Byte data | `DU8 "Hello",0` |
| `DU16` | Word data | `DU16 1234` |
| `DU32` | Dword data | `DU32 0x12345678` |
| `DU64` | Qword data | `DU64 0xDEADBEEF` |

#### Instructions Supported

Currently generating:
- ✅ Data movement: `MOV`, `PUSH`, `POP`, `LEA`
- ✅ Arithmetic: `ADD`, `SUB`, `IMUL`, `IDIV`, `NEG`
- ✅ Bitwise: `AND`, `OR`, `XOR`, `NOT`, `SHL`, `SHR`
- ✅ Comparisons: `CMP`, `TEST`
- ✅ Control flow: `JMP`, `JE`, `JNE`, `JL`, `JLE`, `JG`, `JGE`, `CALL`, `RET`
- ✅ FPU (x87): `FLD`, `FST`, `FSTP`, `FADD`, `FSUB`, `FMUL`, `FDIV`, `FNEG`

#### Label Syntax

| Type | Syntax | Example | Purpose |
|------|--------|---------|---------|
| Local | `@@label:` | `@@loop:` | Function-local label |
| Global | `label:` | `Main:` | Global label |
| Exported | `label::` | `GetAnswer::` | Exported symbol |

### Assembler Parser Status

**Current Status**: ⚠️ **Partial Implementation**

The assembler can:
- ✅ Define register encodings
- ✅ Map register names to IDs
- ⚠️ Parse assembly (skeleton only)
- ⚠️ Encode to machine code (incomplete)

**What's Missing**:
1. Full instruction parser (currently only framework exists)
2. Operand parsing (registers, immediates, memory, labels)
3. Machine code encoder for all x64 instructions
4. Label resolution and relocation
5. Multi-pass assembly for forward references

### Proposed Assembler Architecture

```
┌──────────────────────────────────────┐
│         hcas (assembler)           │
├──────────────────────────────────────┤
│  Input:  TempleOS-style .asm/.ASM    │
│  Output: .o (object file)            │
│          or .bin (raw binary)        │
└──────────────────────────────────────┘
         │
         ├─► Parser (text → IR)
         ├─► Encoder (IR → machine code)
         ├─► Linker (resolve labels)
         └─► Writer (output formats)
```

**Proposed CLI**:
```bash
hcas input.asm -o output.o         # ELF object file
hcas input.asm -o output.bin -f bin # Raw binary
hcas input.asm -l listing.lst       # With listing file
hcas -S source.HC -o output.asm     # From C (if integrated)
```

---

## 3. Assembly Generation (Compiler → Assembly)

### Current Generator (src/codegen/x64.zig)

**Purpose**: Convert IR → TempleOS Assembly Text

**Features**:
- ✅ Data section emission (strings, globals)
- ✅ Text section emission (functions)
- ✅ Stack frame management
- ✅ Register allocation (simple)
- ✅ Instruction selection
- ✅ Label management

**Output Format**: Pure TempleOS syntax
```asm
//TempleOS-style x64 Assembly

//Read-only data section
.str0:
	DU8	"Hello, World!",0

//Code section
Main::
	PUSH	RBP
	MOV	RBP,RSP
	SUB	RSP,16
	MOV	RAX,42
	POP	RBP
	RET
```

---

## 4. Missing Directives & Features

### High Priority

1. **Assembler Parser** - Complete implementation
   - Parse all instruction mnemonics
   - Parse operands (reg, imm, mem, label)
   - Handle label definitions
   - Support comments

2. **Machine Code Encoder** - Full x64 encoding
   - MOD/RM byte generation
   - SIB byte for complex addressing
   - REX prefix for 64-bit operations
   - Immediate encoding

3. **Preprocessor Expressions** - `#if` with math
   ```c
   #if VERSION > 2
   ...
   #endif
   ```

4. **Object File Format** - ELF/COFF output
   - Symbol table
   - Relocation entries
   - Section headers

### Medium Priority

5. **`#elif`** - Chained conditionals
6. **`#undef`** - Remove macros
7. **`#assert`** - Compile-time checks
8. **`#error` / `#warning`** - User messages
9. **Listing File Generation** - Address + hex + source
10. **Multi-pass Assembly** - Forward label references

### Low Priority

11. **`#help_index`** - Documentation (TempleOS-specific)
12. **`#pragma`** - Compiler hints
13. **Macro parameters** - `#define FOO(x) ((x) * 2)`
14. **String concatenation** - Adjacent string literals

---

## 5. Extraction Plan

### Phase 1: Standalone Preprocessor (`hcpp`)

**Week 1-2**:
1. Create `src/tools/hcpp.zig`
2. Extract preprocessor as self-contained module
3. Add CLI: `-D`, `-I`, `-o`, `--help`
4. Add test suite for standalone operation
5. Update main compiler to use `hcpp` as library

**Deliverables**:
- `hcpp` binary
- `hcpp --version`
- `hcpp input.HC -o output.i`

### Phase 2: Complete Assembler (`hcas`)

**Week 3-5**:
1. Finish assembler parser (instruction + operand parsing)
2. Implement machine code encoder
3. Add label resolution (multi-pass)
4. Create `src/tools/hcas.zig`
5. CLI: `-o`, `-f [elf|bin]`, `-l listing`
6. Test with hand-written assembly files

**Deliverables**:
- `hcas` binary
- Parse TempleOS assembly syntax
- Generate ELF `.o` or raw `.bin`

### Phase 3: Refactor Compiler (`hcc`)

**Week 6**:
1. Update compiler to use standalone tools
2. Pipeline: `hcc` → IR → text asm → `hcas` → binary
3. Option to output intermediate files
4. Add `-S` (stop at assembly), `-c` (stop at object)

**Deliverables**:
- `hcc -S input.HC` → generates `.asm`
- `hcc -c input.HC` → generates `.o`
- `hcc input.HC` → generates executable

---

## 6. Tool Interactions

### Proposed Pipeline

```
┌─────────┐      ┌────────┐      ┌────────┐      ┌─────────┐
│ foo.HC  │─────→│ hcpp │─────→│ hcc │─────→│ hcas  │
└─────────┘      └────────┘      └────────┘      └─────────┘
   source       preprocessor     compiler        assembler
                     ↓                ↓               ↓
                  foo.i           foo.asm         foo.o
```

### Standalone Use Cases

**Preprocessor Only**:
```bash
hcpp source.HC -o preprocessed.i
```

**Assembler Only**:
```bash
hcas mycode.asm -o mycode.o
```

**Full Compilation** (orchestrated by `hcc`):
```bash
hcc source.HC              # → a.out (full pipeline)
hcc -E source.HC           # → stdout (preprocess only)
hcc -S source.HC           # → source.asm (stop at assembly)
hcc -c source.HC           # → source.o (stop at object)
hcc source1.o source2.o    # → link objects
```

---

## 7. Testing Strategy

### Preprocessor Tests
- [ ] Macro expansion
- [ ] Conditional compilation
- [ ] File inclusion (with recursion limits)
- [ ] `#define`, `#ifdef`, `#ifndef`, `#else`, `#endif`
- [ ] `#if` expressions (when implemented)
- [ ] `#exe` compile-time execution

### Assembler Tests
- [ ] Parse all instruction forms
- [ ] Encode common instructions
- [ ] Label resolution (forward/backward)
- [ ] Relocation generation
- [ ] ELF object file output
- [ ] Round-trip: asm → machine code → disasm → asm

### Integration Tests
- [ ] Full pipeline: `.HC` → `.i` → `.asm` → `.o` → executable
- [ ] Compiler with `-E`, `-S`, `-c` flags
- [ ] Link multiple object files
- [ ] Mixed C/assembly files

---

## 8. Compatibility Goals

### TempleOS Compatibility

**Must Have**:
- ✅ TempleOS assembly syntax (current)
- ✅ x87 FPU instructions (current)
- ✅ Preprocessor directives (mostly done)
- ⚠️ Data directives (DU8, DU16, DU32, DU64)
- ⚠️ Label syntax (`:`, `::`, `@@`)

**Nice to Have**:
- `#help_index` (documentation system)
- Macro parameters
- More preprocessor functions

### Linux Compatibility

**Must Have**:
- ✅ ELF executable generation (current)
- ✅ ELF object file generation (partial)
- ✅ System call support (current)
- ⚠️ Shared library support (future)

---

## 9. Recommendations

### Immediate Actions (This Week)

1. ✅ **This Audit** - Document current state
2. **Begin Phase 1** - Extract preprocessor
   - Create `src/tools/hcpp.zig`
   - Add CLI scaffolding
   - Write standalone tests

### Short Term (Next 2 Weeks)

3. **Complete Preprocessor** (`hcpp`)
   - Add missing directives (`#if`, `#elif`)
   - Implement expression evaluator
   - Polish CLI

4. **Start Assembler Parser** (`hcas`)
   - Implement full instruction parser
   - Add operand parsing
   - Test with simple assembly files

### Medium Term (Next Month)

5. **Complete Assembler** (`hcas`)
   - Finish machine code encoder
   - Add label resolution
   - Generate ELF objects

6. **Refactor Compiler** (`hcc`)
   - Use standalone tools as pipeline
   - Add `-E`, `-S`, `-c` flags
   - Update build system

---

## 10. Open Questions

1. **Linker**: Do we need a separate linker tool (`holyld`)?
   - Currently `hcc` generates executables directly
   - May want separate link stage for multi-file projects

2. **Object Format**: ELF only, or also COFF for Windows?
   - Current: Linux/ELF only
   - Future: Cross-platform?

3. **Assembler Syntax**: Strict TempleOS only, or also AT&T/Intel?
   - Current: TempleOS only
   - Could support multiple dialects?

4. **Macro Parameters**: How complex should they be?
   - TempleOS: Simple token replacement
   - GCC-style: Full preprocessor functions?

5. **Inline Assembly**: Keep current "raw" model or add constraints?
   - Current: Raw bytes, no integration
   - Future: GCC-style extended asm?

---

## Appendix A: File Structure (Proposed)

```
src/
├── tools/
│   ├── hcpp.zig          # Standalone preprocessor
│   ├── hcas.zig          # Standalone assembler
│   └── hcc.zig          # Main compiler (orchestrator)
├── preprocessor/
│   ├── preprocessor.zig    # Preprocessor library
│   └── interpreter.zig     # #exe support
├── assembler/
│   ├── assembler.zig       # Assembler interface
│   ├── x64.zig             # x64 implementation
│   └── parser.zig          # Assembly parser
├── codegen/
│   ├── ir.zig              # Intermediate representation
│   ├── ir_builder.zig      # IR construction
│   ├── x64.zig             # Assembly generator
│   └── x64_machine_code.zig # Direct machine code gen
└── main.zig                # Main entry (calls tools)
```

---

## Appendix B: Reference Implementation Checklist

### Preprocessor (`hcpp`)
- [x] `#define`
- [x] `#include`
- [x] `#ifdef` / `#ifndef`
- [x] `#else` / `#endif`
- [x] `#exe`
- [ ] `#if` (with expressions)
- [ ] `#elif`
- [ ] `#undef`
- [ ] `#assert`
- [ ] `#error` / `#warning`
- [ ] Macro parameters

### Assembler (`hcas`)
- [ ] Parse all x64 instructions
- [ ] Parse register operands
- [ ] Parse immediate operands
- [ ] Parse memory operands
- [ ] Parse labels
- [ ] Encode MOV instructions
- [ ] Encode arithmetic instructions
- [ ] Encode control flow
- [ ] Label resolution (multi-pass)
- [ ] Generate ELF object files
- [ ] Generate symbol table
- [ ] Generate relocations

### Compiler (`hcc`)
- [x] Lexer
- [x] Parser
- [x] Semantic analysis
- [x] IR generation
- [x] Assembly generation
- [x] Machine code generation (direct)
- [ ] Use `hcpp` for preprocessing
- [ ] Use `hcas` for assembly
- [ ] Add `-E`, `-S`, `-c` flags
- [ ] Multi-file linking

---

**End of Audit**
