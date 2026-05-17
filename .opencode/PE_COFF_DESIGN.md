# PE32+ and COFF Implementation Design

## Overview
Implement Windows x64 executable (PE32+) and object file (COFF) support for cross-compilation.

## Format Specifications

### COFF Object Files (.obj)
- **Purpose**: Intermediate object files (like ELF .o files)
- **Structure**:
  - COFF File Header (20 bytes)
  - Optional Section Headers
  - Section Data (.text, .data, .rdata, .bss)
  - Symbol Table
  - String Table
  - Relocations

### PE32+ Executables (.exe)
- **Purpose**: Windows x64 executables
- **Structure**:
  - DOS Header (64 bytes) + DOS Stub
  - PE Signature ("PE\0\0")
  - COFF File Header (20 bytes)
  - Optional Header (PE32+, 240 bytes)
  - Section Headers
  - Section Data (.text, .rdata, .data, .idata, .reloc)
  - Import Directory (for DLL imports)
  - Base Relocation Table

## Key Differences from ELF

### 1. File Headers
- **ELF**: Single header with magic bytes `\x7FELF`
- **PE32+**: DOS header + PE signature + COFF header + Optional header
- **DOS Stub**: Required for backward compatibility (prints "This program cannot be run in DOS mode")

### 2. Sections vs Segments
- **ELF**: Uses segments (PT_LOAD) for runtime loading
- **PE**: Uses sections with alignment requirements
  - File alignment: typically 512 bytes
  - Section alignment: typically 4096 bytes (page size)

### 3. Imports/External Symbols
- **ELF**: Uses PLT/GOT with dynamic linker
- **PE**: Uses Import Directory + Import Address Table (IAT)
  - Each DLL gets an Import Descriptor
  - Function names in Import Name Table (INT)
  - Addresses filled by loader into IAT

### 4. Calling Convention
- **Linux x64 (System V)**: RDI, RSI, RDX, RCX, R8, R9 + stack
- **Windows x64 (fastcall)**: RCX, RDX, R8, R9 + stack
  - **Shadow space**: Caller allocates 32 bytes (4×8) on stack for callee to save registers
  - Stack must be 16-byte aligned before CALL
  - Return values in RAX (or XMM0 for floats)

### 5. Entry Point
- **ELF**: `_start` symbol, direct execution
- **PE**: `mainCRTStartup` or custom entry point defined in Optional Header
  - Can use `WinMain` for GUI apps
  - Can use custom entry point without CRT

## Implementation Plan

### Phase 1: COFF Object Writer (src/codegen/coff_object.zig)
Similar to `elf_object.zig`:
- COFF File Header
- Section headers for .text, .data, .rdata, .bss
- Symbol table (internal symbols, external references)
- Relocations (IMAGE_REL_AMD64_*)
- String table for long symbol names

### Phase 2: PE32+ Executable Writer (src/codegen/pe_writer.zig)
Similar to `elf_writer.zig`:
- DOS header + stub
- PE signature
- COFF file header
- Optional header (PE32+)
- Section headers
- Import directory for kernel32.dll, msvcrt.dll, etc.
- Base relocation table (if needed)

### Phase 3: Windows Calling Convention (src/codegen/x64_machine_code.zig)
- Add `CallingConvention` enum: `.sysv`, `.win64`
- Modify function prologue/epilogue
- Add shadow space allocation for Windows
- Change parameter passing order (RCX, RDX, R8, R9)

### Phase 4: Target Selection (src/main.zig, src/compiler.zig)
- Add `--target` flag: `linux-x64`, `windows-x64`, `templeos`
- Route to appropriate writer based on target
- Set calling convention based on target

## COFF Structures (Windows x64)

### COFF File Header
```zig
const COFFHeader = extern struct {
    machine: u16,              // 0x8664 for x64
    number_of_sections: u16,
    time_date_stamp: u32,
    pointer_to_symbol_table: u32,
    number_of_symbols: u32,
    size_of_optional_header: u16,  // 0 for object files
    characteristics: u16,
};
```

### Section Header
```zig
const SectionHeader = extern struct {
    name: [8]u8,               // Section name (or string table offset)
    virtual_size: u32,
    virtual_address: u32,
    size_of_raw_data: u32,
    pointer_to_raw_data: u32,
    pointer_to_relocations: u32,
    pointer_to_linenumbers: u32,
    number_of_relocations: u16,
    number_of_linenumbers: u16,
    characteristics: u32,      // Flags (execute, read, write, etc.)
};
```

### Symbol Table Entry
```zig
const SymbolTableEntry = extern struct {
    name: [8]u8,              // Symbol name or string table offset
    value: u32,
    section_number: i16,       // 1-based, or special values
    type: u16,
    storage_class: u8,
    number_of_aux_symbols: u8,
};
```

### Relocation Entry
```zig
const RelocationEntry = extern struct {
    virtual_address: u32,      // Offset in section
    symbol_table_index: u32,
    type: u16,                 // IMAGE_REL_AMD64_*
};
```

## PE32+ Structures

### DOS Header
```zig
const DOSHeader = extern struct {
    e_magic: u16,              // 0x5A4D ("MZ")
    e_cblp: u16,
    e_cp: u16,
    // ... (28 fields total)
    e_lfanew: u32,             // Offset to PE header (at offset 0x3C)
};
```

### PE Optional Header (PE32+)
```zig
const OptionalHeaderPE32Plus = extern struct {
    magic: u16,                // 0x20B for PE32+
    major_linker_version: u8,
    minor_linker_version: u8,
    size_of_code: u32,
    size_of_initialized_data: u32,
    size_of_uninitialized_data: u32,
    address_of_entry_point: u32,  // RVA of entry point
    base_of_code: u32,
    image_base: u64,           // Preferred load address (0x140000000 for x64)
    section_alignment: u32,    // Usually 0x1000 (4KB)
    file_alignment: u32,       // Usually 0x200 (512B)
    // ... version fields ...
    size_of_image: u32,
    size_of_headers: u32,
    checksum: u32,
    subsystem: u16,            // 2=GUI, 3=Console
    dll_characteristics: u16,
    // ... stack/heap sizes (u64) ...
    number_of_rva_and_sizes: u32,  // Usually 16
    data_directory: [16]DataDirectory,
};

const DataDirectory = extern struct {
    virtual_address: u32,      // RVA
    size: u32,
};
```

### Import Descriptor
```zig
const ImportDescriptor = extern struct {
    original_first_thunk: u32,  // RVA to INT (Import Name Table)
    time_date_stamp: u32,
    forwarder_chain: u32,
    name: u32,                  // RVA to DLL name
    first_thunk: u32,           // RVA to IAT (Import Address Table)
};
```

## Windows DLL Imports

Common imports for console programs:
- **kernel32.dll**: `ExitProcess`, `GetStdHandle`, `WriteConsoleA`
- **msvcrt.dll**: `printf`, `puts`, `exit`, `malloc`, `free`

Import by name:
```zig
const ImportByName = extern struct {
    hint: u16,                 // Index into export table (or 0)
    name: [1]u8,               // Null-terminated name (variable length)
};
```

## Relocation Types (x64)

### COFF Relocations (IMAGE_REL_AMD64_*)
- `ADDR64` (0x0001): 64-bit absolute address
- `ADDR32NB` (0x0003): 32-bit address without image base
- `REL32` (0x0004): 32-bit relative to instruction end
- `SECTION` (0x000A): Section index
- `SECREL` (0x000B): 32-bit offset from section start

### Base Relocations
For ASLR support, if image is loaded at different address:
- Type-offset pairs for each address that needs fixing

## Testing Strategy

1. **Object files**: Compile simple HolyC → .obj, inspect with `dumpbin` (if available) or hex editor
2. **Linking**: Use existing Windows linker (link.exe) to link our .obj files
3. **Executables**: Generate minimal .exe with `ExitProcess(0)`, test on Windows VM or Wine
4. **Full program**: Port `test_hello.hc` to use Windows APIs (`WriteConsoleA` or `msvcrt.printf`)

## File Organization

```
src/codegen/
  ├── coff_object.zig        # COFF .obj writer
  ├── pe_writer.zig          # PE32+ .exe writer
  ├── elf_object.zig         # (existing) ELF .o writer
  ├── elf_writer.zig         # (existing) ELF executable writer
  ├── templeos_bin.zig       # (existing) TempleOS .BIN writer
  └── compiler.zig           # Route to correct writer based on target

src/target.zig               # Target triple definition and detection
```

## Next Steps

1. ✅ Create this design document
2. Implement `src/target.zig` for target selection
3. Implement COFF object writer
4. Add Windows calling convention to x64 code generator
5. Implement PE32+ executable writer
6. Add import table generation
7. Update compiler to support `--target windows-x64`
8. Test with Wine or Windows VM

## References

- Microsoft PE/COFF Specification: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
- COFF Symbol Table: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#coff-symbol-table
- x64 Calling Convention: https://learn.microsoft.com/en-us/cpp/build/x64-calling-convention
- Import Tables: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format#import-directory-table
