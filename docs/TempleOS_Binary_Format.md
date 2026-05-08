# TempleOS Binary Format Specification

## Overview

TempleOS uses a custom binary format (`.BIN` files) for executable modules. This document specifies the complete format based on research of the TempleOS compiler source code.

## File Structure

A TempleOS binary consists of three main sections:
1. **Header** (`CBinFile` structure, 32 bytes)
2. **Code Section** (x64 machine code)
3. **Patch Table** (relocation and import/export information)

## 1. Binary Header (`CBinFile`)

```c
class CBinFile {
    U16 jmp;                  // Jump instruction over header (typically 0x1EEB)
    U8  module_align_bits;    // Module alignment: 1 << bits (typically 4 = 16 bytes)
    U8  reserved;             // Always 0
    U32 bin_signature;        // Magic number: 'TOSB' (0x42534F54)
    I64 org;                  // Preferred load address (INVALID_PTR = 0x7FFFFFFFFFFFFFFF)
    I64 patch_table_offset;   // File offset to patch table
    I64 file_size;            // Total file size
};
```

### Field Details

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0x00 | 2 | `jmp` | x86 short jump instruction to skip over header into code |
| 0x02 | 1 | `module_align_bits` | Alignment requirement: `1 << bits` bytes |
| 0x03 | 1 | `reserved` | Reserved byte, always 0 |
| 0x04 | 4 | `bin_signature` | Must be `'TOSB'` (0x42534F54 little-endian) |
| 0x08 | 8 | `org` | Preferred load address, or `INVALID_PTR` for dynamic |
| 0x10 | 8 | `patch_table_offset` | Byte offset from start of file to patch table |
| 0x18 | 8 | `file_size` | Total size of binary file in bytes |

### Notes

- The `jmp` field is calculated as: `0xEB + 256 * (sizeof(CBinFile) - 2)` = `0x1EEB`
- Module alignment is typically 16 bytes (`module_align_bits = 4`)
- When `org == INVALID_PTR`, the loader allocates memory dynamically
- The loader jumps to `module_base = file_base + sizeof(CBinFile)` after loading

## 2. Code Section

Immediately following the header (at offset 0x20) is the executable x64 machine code. This section contains:
- Function code
- Inline data (though most data goes in heap allocations)
- Jump tables
- Any compiler-generated code

The code is position-dependent and requires patching by the loader based on the patch table.

## 3. Patch Table

The patch table begins at `patch_table_offset` and consists of a sequence of variable-length entries terminated by `IET_END`.

### Patch Table Entry Types

| Type | Value | Description |
|------|-------|-------------|
| `IET_END` | 0 | Table terminator |
| `IET_REL_I8` | 4 | 8-bit relative relocation |
| `IET_IMM_U8` | 5 | 8-bit immediate value |
| `IET_REL_I16` | 6 | 16-bit relative relocation |
| `IET_IMM_U16` | 7 | 16-bit immediate value |
| `IET_REL_I32` | 8 | 32-bit relative relocation |
| `IET_IMM_U32` | 9 | 32-bit immediate value |
| `IET_REL_I64` | 10 | 64-bit relative relocation |
| `IET_IMM_I64` | 11 | 64-bit immediate value |
| `IET_REL32_EXPORT` | 16 | Export symbol (32-bit relative) |
| `IET_IMM32_EXPORT` | 17 | Export symbol (32-bit immediate) |
| `IET_REL64_EXPORT` | 18 | Export symbol (64-bit relative) |
| `IET_IMM64_EXPORT` | 19 | Export symbol (64-bit immediate) |
| `IET_ABS_ADDR` | 20 | Absolute address relocation list |
| `IET_CODE_HEAP` | 21 | Allocate code heap block |
| `IET_ZEROED_CODE_HEAP` | 22 | Allocate zeroed code heap block |
| `IET_DATA_HEAP` | 23 | Allocate data heap block |
| `IET_ZEROED_DATA_HEAP` | 24 | Allocate zeroed data heap block |
| `IET_MAIN` | 25 | Entry point to call at load time |

### Entry Format: Standard Import/Export

Used for types: `IET_REL_*`, `IET_IMM_*`, `IET_*_EXPORT`, `IET_MAIN`

```
u8   type          // Entry type from table above
u32  rip           // Offset from module_base
char name[]        // NUL-terminated symbol name (can be empty)
```

### Entry Format: `IET_ABS_ADDR`

```
u8   type = 20     // IET_ABS_ADDR
u32  count         // Number of sites to patch
u8   zero          // Always 0
u32  offsets[count] // Array of RIP offsets
```

**Loader behavior**: For each offset, the loader treats the 64-bit value at `module_base + offset` as a module-relative pointer and adds `module_base` to it.

### Entry Format: `IET_DATA_HEAP` / `IET_ZEROED_DATA_HEAP`

```
u8   type          // IET_DATA_HEAP (23) or IET_ZEROED_DATA_HEAP (24)
u32  count         // Number of reference sites
char name[]        // NUL-terminated symbol name (optional)
i64  size          // Size of allocation in bytes
u32  offsets[count] // Array of RIP offsets that reference this data
```

**Loader behavior**: 
1. Allocates `size` bytes on the data heap (zeroed if type is 24)
2. For each offset in the array, adds the allocation address to the 64-bit value at `module_base + offset`
3. If `name` is non-empty, creates an export symbol for the allocation

### Entry Format: `IET_CODE_HEAP` / `IET_ZEROED_CODE_HEAP`

```
u8   type          // IET_CODE_HEAP (21) or IET_ZEROED_CODE_HEAP (22)
u32  count         // Number of reference sites
char name[]        // NUL-terminated symbol name (optional)
i32  size          // Size of allocation in bytes (32-bit!)
u32  offsets[count] // Array of RIP offsets that reference this code
```

Similar to data heap, but allocates on code heap and uses 32-bit size.

## 4. Loading Process

The TempleOS loader (`Load()` in `Kernel/KLoad.HC`) performs these steps:

1. **Read File**: Load entire `.BIN` file into memory
2. **Validate Header**: 
   - Check `bin_signature == 'TOSB'`
   - Verify `module_align_bits` is valid
3. **Allocate Memory**: 
   - If `org == INVALID_PTR`, allocate aligned memory
   - Otherwise, load at specified `org` address
4. **Copy Code**: Copy file contents to final location
5. **Calculate Base**: `module_base = load_address + sizeof(CBinFile)`
6. **Pass 1 (`LoadPass1`)**: Process patch table
   - Resolve imports
   - Apply relocations
   - Allocate heap blocks
7. **Pass 2 (`LoadPass2`)**: Execute `IET_MAIN` entries if present

## 5. Relocation Details

### Absolute Address Relocation (`IET_ABS_ADDR`)

For each offset in the list:
```c
ptr = module_base + offset;
*(u64*)ptr += module_base;
```

The compiler emits module-relative offsets (0, 8, 16, etc.), and the loader converts them to absolute addresses.

### Import Resolution

For import entries (`IET_REL_I32`, etc.):
1. Loader looks up symbol name in hash tables
2. Retrieves symbol's absolute address
3. Patches the code based on entry type:
   - **Relative**: Stores `target - (module_base + rip)` at patch site
   - **Immediate**: Stores absolute address at patch site

### Export Registration

For export entries (`IET_*_EXPORT`):
1. Loader adds symbol to hash table
2. Associates symbol with `module_base + rip`
3. Other modules can import this symbol

## 6. File Size and Padding

Total file size is always rounded up to 16-byte alignment:
```c
file_size = (header_size + code_size + patch_table_size + 15) & ~15;
```

After the `IET_END` entry, the compiler typically emits 16 zero bytes of padding before the file ends.

## 7. Example Binary Structure

```
Offset    | Content
----------|----------------------------------------------------------
0x00      | CBinFile header (32 bytes)
0x20      | Machine code (varies)
...       | 
0x2000    | Patch table begins
          |   IET_ABS_ADDR entry with 5 offsets
          |   IET_DATA_HEAP entry for global string
          |   IET_MAIN entry pointing to Main() function
          |   IET_END
          |   16 bytes of zero padding
0x2100    | EOF (aligned to 16 bytes)
```

## 8. Constraints and Limitations

- Maximum file size: 2^63-1 bytes (I64)
- Module alignment must be power of 2
- Patch table offsets are 32-bit (RIP), limiting module size to 4GB
- Symbol names are NUL-terminated C strings
- No nested or compressed data structures
- All integers are little-endian

## 9. Comparison with ELF

| Feature | TempleOS .BIN | ELF |
|---------|---------------|-----|
| Header size | 32 bytes | 64 bytes (64-bit ELF) |
| Section headers | No | Yes |
| Symbol table | In patch table | Separate .symtab section |
| Relocations | Patch table | .rela sections |
| Dynamic linking | Import/export in patch table | .dynamic section |
| Debug info | Embedded or separate | DWARF sections |
| Complexity | Simple, single-pass | Complex, multi-section |

## 10. References

- **Source**: TempleOS compiler source code archive
  - `/Compiler/CMain.HC` - Binary generation
  - `/Kernel/KLoad.HC` - Loading and patching
  - `/Kernel/KernelA.HH` - Structure definitions
- **Example**: `/Compiler/Compiler.BIN` - Real binary file

## 11. Implementation Notes for Cross-Compilers

1. **Track Relocations**: During code generation, record every site that references module-relative addresses
2. **Use Heap Allocations**: Global variables and string literals should use `IET_DATA_HEAP` entries, not embedded data
3. **Entry Point**: If generating a module with top-level code, emit `IET_MAIN` pointing to initialization function
4. **Module Base**: All code must assume it runs at `module_base`, not absolute zero
5. **Import Symbols**: Use appropriate `IET_REL_*` or `IET_IMM_*` based on instruction encoding requirements
6. **Export Public Symbols**: Any function/variable marked `public` should get an export entry
7. **Alignment**: Respect 16-byte alignment throughout
8. **Testing**: Validate with TempleOS `Load()` function to ensure compatibility
