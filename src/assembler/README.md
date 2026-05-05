# HolyCross Assembler Architecture

This module provides architecture-independent assembly support for HolyCross, following a clean interface pattern that allows easy addition of new target architectures.

## Architecture Overview

```
┌─────────────────────────────────────┐
│         Assembler Interface         │
│  (Architecture-independent API)     │
├─────────────────────────────────────┤
│  - parse(source) -> Instructions    │
│  - encode(insts) -> MachineCode     │
│  - getRegisterName(id) -> String    │
│  - getRegisterId(name) -> ID        │
└─────────────────────────────────────┘
            ▲         ▲         ▲
            │         │         │
    ┌───────┴───┐  ┌──┴──┐  ┌──┴─────┐
    │    x64    │  │ARM64│  │ RISC-V │
    │ (current) │  │(todo)│  │ (todo) │
    └───────────┘  └─────┘  └────────┘
```

## File Structure

```
src/assembler/
├── assembler.zig          # Interface definition
├── x64.zig                # x64/AMD64 implementation
├── tests/
│   └── assembler_tests.zig # Test suite
└── README.md              # This file
```

## Current Status

### ✅ Implemented
- **Interface Layer**: Complete abstraction for architecture-independent code
- **x64 Skeleton**: Register definitions, name/ID lookup
- **Type System**: Operand types (register, immediate, memory, label)
- **Instruction Structure**: Generic instruction representation
- **Test Suite**: Comprehensive tests for the architecture

### 🚧 In Progress
- **x64 Parser**: Parse assembly text into Instructions
- **x64 Encoder**: Generate x64 machine code from Instructions

### 📋 Future Work
- **Full x64 Support**: All common instructions (MOV, ADD, SUB, etc.)
- **ARM64**: Add ARM64 architecture support
- **RISC-V**: Add RISC-V architecture support
- **Optimization**: Instruction selection and optimization passes

## Usage Example

```zig
const assembler = @import("assembler.zig");

// Create an x64 assembler
var x64 = assembler.X64Assembler.init(allocator);
defer x64.deinit();

// Get the architecture-independent interface
const asm_interface = x64.asAssembler();

// Use the interface (works for any architecture)
const reg_name = asm_interface.getRegisterName(0, .qword); // "RAX"
const reg_id = try asm_interface.getRegisterId("RBX");     // 3

// Parse assembly (future)
const instructions = try asm_interface.parse(
    "MOV RAX, RBX\nPUSH RCX\n",
    allocator
);

// Encode to machine code (future)
const machine_code = try asm_interface.encode(instructions, allocator);
```

## Adding a New Architecture

To add support for a new architecture (e.g., ARM64):

1. **Create the implementation file** (`arm64.zig`)
2. **Define the register enum** for your architecture
3. **Implement the required methods**:
   - `parse(source)` - Parse assembly text
   - `encode(instructions)` - Generate machine code
   - `getRegisterName(id, size)` - Register ID to name
   - `getRegisterId(name)` - Register name to ID
   - `deinit()` - Clean up resources
4. **Add tests** in `tests/`
5. **Export** in `../assembler.zig`

### Example Template

```zig
pub const ARM64Assembler = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ARM64Assembler {
        return .{ .allocator = allocator };
    }
    
    pub fn deinit(self: *ARM64Assembler) void {
        _ = self;
    }
    
    pub fn parse(self: *ARM64Assembler, source: []const u8, allocator: std.mem.Allocator) ![]Instruction {
        // Implement ARM64 assembly parsing
    }
    
    pub fn encode(self: *ARM64Assembler, instructions: []Instruction, allocator: std.mem.Allocator) ![]u8 {
        // Implement ARM64 machine code generation
    }
    
    pub fn getRegisterName(self: *ARM64Assembler, reg_id: u8, size: OperandSize) []const u8 {
        // Return ARM64 register names (X0-X30, W0-W30, etc.)
    }
    
    pub fn getRegisterId(self: *ARM64Assembler, name: []const u8) !u8 {
        // Parse ARM64 register names
    }
    
    pub fn asAssembler(self: *ARM64Assembler) Assembler {
        return assembler.assembler(self);
    }
};
```

## Design Principles

1. **Architecture Independence**: Core compiler code should work with any target architecture
2. **Clean Interfaces**: VTable-based polymorphism for runtime architecture selection
3. **Zero-Cost Abstraction**: Interface overhead only at parse/encode boundaries
4. **Extensibility**: Easy to add new architectures without modifying existing code
5. **Type Safety**: Strong typing for operands, registers, and sizes

## Register Encoding

### x64 Registers

All x64 registers use a unified encoding scheme:
- **ID 0-15**: General-purpose registers (RAX-R15)
- **Size determined by operand size**:
  - `.byte` = 8-bit (AL, BL, etc.)
  - `.word` = 16-bit (AX, BX, etc.)
  - `.dword` = 32-bit (EAX, EBX, etc.)
  - `.qword` = 64-bit (RAX, RBX, etc.)

Example:
```
ID 0 + .qword = RAX
ID 0 + .dword = EAX
ID 0 + .word  = AX
ID 0 + .byte  = AL
```

## Testing

Run the test suite:
```bash
zig build test
```

Tests cover:
- Interface abstraction
- Register name/ID lookups
- Architecture switching
- Future: Parser and encoder tests
