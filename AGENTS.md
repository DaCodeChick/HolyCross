# AGENTS.md - AI Agent Guidance for HolyCross

## Project Status
**Pre-Alpha - No Backward Compatibility Guarantees**

This project is in active early development. Breaking changes are expected and encouraged when they improve the design. Do not maintain backward compatibility with previous iterations unless explicitly required.

## Goal
Cross-compile HolyC to multiple platforms:
- Linux x64 (ELF)
- Windows x64 (PE32+ / COFF)
- TempleOS/ZealOS (BIN format)

## Architecture

### Target System (`src/target.zig`)
- Unified target triple parser: `arch-os-abi` (e.g., `x64-linux-gnu`, `x64-windows-msvc`)
- Supports:
  - OS: Linux, Windows, TempleOS
  - Arch: x64
  - ABI: GNU, MSVC, none
- Provides calling convention, object format, and executable format mapping

### File Format Writers
- `src/codegen/elf_writer.zig` - Linux ELF executables ✓
- `src/codegen/elf_object.zig` - Linux ELF `.o` object files ✓
- `src/codegen/coff_object.zig` - Windows COFF `.obj` object files ✓
- `src/codegen/pe_writer.zig` - Windows PE32+ `.exe` executables ✓
- `src/codegen/macho_object.zig` - macOS Mach-O `.o` object files ✓
- `src/codegen/templeos_bin.zig` - TempleOS/ZealOS `.BIN` format ✓

### Code Generation
- `src/codegen/x64_machine_code.zig` - ABI-aware x64 machine code generation
  - Supports System V (Linux) and Win64 calling conventions
  - `CodeBuffer` union routes output to appropriate writer
  - Handles relocations and extern symbols for each format
  - Uses unified external symbol table for tracking imported functions

- `src/codegen/external_symbols.zig` - Unified external symbol tracking
  - `ExternalSymbolTable` tracks all imported functions and their call sites
  - `ExternalSymbol` represents an imported function with library hints
  - `SymbolReference` tracks individual call sites for patching/relocation
  - Prepares for PLT/GOT (Linux) and IAT stub (Windows) generation

### Compiler Pipeline (`src/codegen/compiler.zig`)
1. Parse AST → IR
2. Generate x64 machine code with correct calling convention
3. Route to appropriate writer based on target
4. Handle linking if needed (external symbols)

## Command-Line Interface
```bash
hcc [options] <input.hc> [output]

Options:
  -S                    Emit assembly only
  -c                    Compile to object file
  -o <file>             Output file
  --target=<triple>     Target triple (default: native)

Examples:
  hcc hello.hc                           # Native platform
  hcc --target=x64-windows-msvc hello.hc # Windows MSVC
  hcc --target=x64-windows-gnu hello.hc  # Windows MinGW
  hcc -c hello.hc -o hello.obj           # Object file
```

## Key Decisions
1. **No legacy compatibility**: Break things freely to improve design
2. **Target triples** over enum-based targets for extensibility
3. **Unified CodeBuffer** interface for all output formats
4. **Calling conventions** determined by target OS/ABI
5. **MinGW support** as `x64-windows-gnu` ABI
6. **Deterministic builds**: Timestamps set to 0 in COFF/PE

## Known Issues / TODOs

### High Priority
- **macOS Mach-O executable/dylib support**: Object files work, but no executable/dylib writer yet
  - Can generate `.o` files successfully
  - Need Mach-O executable writer for standalone apps
  - Need Mach-O dylib writer for shared libraries
  - See macOS ld64 documentation for linking requirements

### Medium Priority
- **No shared library output**: Can't generate `.so` or `.dll` files yet
  - Executables and object files work fine
  - Shared libraries need PLT/GOT (Linux) generation
  - See docs/PLT_GOT_DESIGN.md for implementation plan (future)
- **Limited relocation types**: Only R_X86_64_PLT32 (ELF), REL32 (COFF), and X86_64_RELOC_BRANCH (Mach-O) supported
  - Sufficient for current object file/executable workflow
  - Shared libraries will need R_X86_64_GLOB_DAT, R_X86_64_JUMP_SLOT

### Low Priority / Future Work
- **No Windows MinGW testing**: `x64-windows-gnu` target untested
- **No symbol versioning**: Linux symbol versions not tracked
- **Stack arguments**: Only register parameters supported (max 6 SysV, 4 Win64)
- **Empty ArrayList workaround**: Zig 0.16 bug requires special deinit logic (documented in ZIG_0.16_NOTES.md)

## Testing
```bash
zig build                          # Build compiler
./zig-out/bin/hcc tests/test_hello.hc -o /tmp/test_hello
/tmp/test_hello                    # Should print "Hello from HolyC!"

zig build test                     # Run test suite (216/217 passing)
```

## Recent Changes
- **2026-05-17**: String escape sequences now working!
  - Added `unescapeString()` to process `\n`, `\t`, `\r`, `\\`, `\"`, `\0`
  - Fixed IR builder to use processed strings from `string_table`
  - Fixed memory leak in `Module.deinit()` by freeing unescaped strings
  - Tested on Windows (Wine) and Linux - output now correct

- **2026-05-17**: Windows PE executables fully tested and working!
  - Successfully tested with Wine on Linux
  - `test_hello.hc` runs correctly
  - `test_windows_api.hc` with multi-DLL imports (msvcrt.dll + kernel32.dll) works
  - `test_context_keywords.hc` executes successfully
  - IAT stubs, import tables, and relocations all functioning correctly

- **2026-05-17**: Fixed test suite (216/217 tests passing)
  - Added missing `is_variadic` parameter to all function test fixtures
  - Updated `defineFunction()` calls in symbol table tests
  - Fixed outdated string expression test
  - All tests now compile and run successfully

- **2026-05-17**: Mach-O object writer for macOS fully working!
  - Created `src/codegen/macho_object.zig` for `.o` output on macOS
  - Integrated with `CodeBuffer` union in `x64_machine_code.zig`
  - Added external symbol and relocation support for Mach-O (X86_64_RELOC_BRANCH)
  - Fixed all Zig 0.16 API issues:
    - ArrayList initialization without .allocator field
    - writeStruct requires endianness parameter  
    - Manual position tracking (no getPos())
    - **Critical fix**: Must use `buffered_writer.interface.writeAll()` directly, not via extracted var
  - Successfully generates valid 635-byte Mach-O object files
  - Verified with `file` command: "Mach-O 64-bit x86_64 object"
  - Contains proper headers, segments (__TEXT, __DATA), sections (__text, __data, __bss)
  - Symbol table and relocations correctly formatted
  - Ready for linking with macOS ld (untested on actual macOS)

- **2026-05-17**: Extended DLL mapping with comprehensive function database
  - Added `getDLLHint()` with 40+ msvcrt.dll and 30+ kernel32.dll functions
  - Covers stdio, memory, strings, process, console, file I/O, synchronization
  - Multi-DLL imports now work correctly (verified with test_windows_api.hc)
  - Default fallback to msvcrt.dll for unknown functions

- **2026-05-17**: Implemented IAT stub generation for Windows PE executables
  - Added `generateIATStubs()` to create RIP-relative jump stubs
  - Added `patchPEImports()` to patch call sites to stubs
  - Each stub is 6 bytes: `FF 25 [offset]` (jmp qword ptr [rip+offset])
  - Verified correct disassembly: calls → stubs → IAT entries
  - Windows PE executables now have complete import mechanism

- **2026-05-17**: Integrated unified external symbol table
  - Created `src/codegen/external_symbols.zig` for cross-platform symbol tracking
  - Refactored `x64_machine_code.zig` to use `ExternalSymbolTable` instead of `CallSite` list
  - Added library hint support for Windows DLL imports (msvcrt.dll)
  - Prepared infrastructure for PLT/GOT (Linux) and IAT stub (Windows) generation
  - Fixed ArrayList memory management issues in forward_jumps deinit

- **2024-05-17**: Added Windows cross-compilation support
  - Implemented `src/target.zig` with target triple parsing
  - Added COFF object writer (`src/codegen/coff_object.zig`)
  - Added PE32+ executable writer (`src/codegen/pe_writer.zig`)
  - Updated x64 machine code generator with Win64 calling convention
  - Wired `--target` flag through compiler pipeline
  - Fixed Zig 0.16 API compatibility (ArrayList, std.time)

## Development Notes
- **Zig Version**: 0.16.0 (see `docs/ZIG_0.16_NOTES.md` for API quirks and gotchas)
- **Allocator Strategy**: Debug builds use DebugAllocator, release uses ArenaAllocator
- **File I/O**: All writers use buffered `std.io.Writer`
- **Design Docs**: See `docs/PE_COFF_DESIGN.md` for Windows format details
