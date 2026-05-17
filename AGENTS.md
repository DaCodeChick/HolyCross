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
- `src/codegen/elf_writer.zig` - Linux ELF executables
- `src/codegen/elf_object.zig` - Linux ELF `.o` object files
- `src/codegen/coff_object.zig` - Windows COFF `.obj` object files
- `src/codegen/pe_writer.zig` - Windows PE32+ `.exe` executables
- `src/codegen/templeos_bin.zig` - TempleOS/ZealOS `.BIN` format

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
- Test suite has unrelated failures (missing `is_variadic` fields in old test data)
- Windows cross-compilation needs end-to-end testing
- PE import resolution is basic (assumes msvcrt.dll)
- No actual linking with external libraries yet

## Testing
```bash
zig build                          # Build compiler
./zig-out/bin/hcc tests/test_hello.hc -o /tmp/test_hello
/tmp/test_hello                    # Should print "Hello from HolyC!"
```

## Recent Changes
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
- **Zig Version**: 0.16.0
- **Allocator Strategy**: Debug builds use DebugAllocator, release uses ArenaAllocator
- **File I/O**: All writers use buffered `std.Io.Writer`
- **Design Docs**: See `docs/PE_COFF_DESIGN.md` for Windows format details
