//! Assembler Interface
//!
//! This module defines the abstract interface that all architecture-specific
//! assemblers must implement. This allows HolyCross to support multiple
//! target architectures (x64, ARM64, RISC-V, etc.) through a common interface.

const std = @import("std");

/// Operand size in bytes
pub const OperandSize = enum(u8) {
    byte = 1,   // 8-bit
    word = 2,   // 16-bit
    dword = 4,  // 32-bit
    qword = 8,  // 64-bit
};

/// Memory operand type
pub const MemoryOperand = struct {
    base: ?u8,        // Base register (if any)
    index: ?u8,       // Index register (if any)
    scale: u8,        // Scale factor (1, 2, 4, 8)
    displacement: i32, // Displacement offset
    size: OperandSize,
    segment: ?u8,     // Segment override (if any)
};

/// Common operand types across architectures
pub const OperandType = union(enum) {
    /// Register operand
    register: struct {
        id: u8,
        size: OperandSize,
    },
    
    /// Immediate value
    immediate: struct {
        value: i64,
        size: OperandSize,
    },
    
    /// Memory operand (e.g., [base + index*scale + displacement])
    memory: MemoryOperand,
    
    /// Label reference (for jumps/calls)
    label: struct {
        name: []const u8,
        is_local: bool, // Local labels (@@label) vs global (label:)
    },
};

/// Instruction or directive representation
pub const Instruction = struct {
    mnemonic: []const u8,
    operands: []OperandType,
    location: struct {
        line: usize,
        column: usize,
    },
    
    /// Optional directive data for DU8/DU16/DU32/DU64, IMPORT, etc.
    directive: ?Directive = null,
};

/// Directive types for assembler directives
pub const Directive = union(enum) {
    /// Data definition (DU8, DU16, DU32, DU64)
    data: struct {
        size: OperandSize, // .byte, .word, .dword, .qword
        values: []const u8, // Raw bytes to emit
    },
    
    /// Mode switch (USE16, USE32, USE64)
    use_mode: enum { use16, use32, use64 },
    
    /// Import external symbols
    import_symbols: []const []const u8,
    
    /// Alignment directive
    align_directive: struct {
        boundary: usize,
        fill_byte: u8,
    },
    
    /// Origin directive
    org: usize,
    
    /// Binary file inclusion
    binfile: []const u8,
    
    /// Listing control
    list_control: enum { list, nolist },
};

/// Label definition
pub const Label = struct {
    name: []const u8,
    offset: usize,
    is_exported: bool, // :: vs :
    is_local: bool,    // @@ prefix
};

/// Assembly parse error
pub const AssemblerError = error{
    UnknownInstruction,
    InvalidOperand,
    InvalidRegister,
    InvalidImmediate,
    InvalidMemoryOperand,
    UnresolvedLabel,
    DuplicateLabel,
    OutOfMemory,
    SyntaxError,
    OperandSizeMismatch,
    UnsupportedOperandSize,
};

/// Architecture-specific assembler interface
///
/// Each target architecture (x64, ARM64, etc.) implements this interface
/// to provide assembly parsing and machine code generation.
pub const Assembler = struct {
    const Self = @This();
    
    /// Function pointer table for polymorphism
    ptr: *anyopaque,
    vtable: *const VTable,
    
    pub const VTable = struct {
        /// Parse assembly source into instructions
        parse: *const fn (ptr: *anyopaque, source: []const u8, allocator: std.mem.Allocator) AssemblerError![]Instruction,
        
        /// Encode instructions to machine code
        encode: *const fn (ptr: *anyopaque, instructions: []Instruction, allocator: std.mem.Allocator) AssemblerError![]u8,
        
        /// Get register name by ID
        getRegisterName: *const fn (ptr: *anyopaque, reg_id: u8, size: OperandSize) []const u8,
        
        /// Get register ID by name
        getRegisterId: *const fn (ptr: *anyopaque, name: []const u8) AssemblerError!u8,
        
        /// Clean up resources
        deinit: *const fn (ptr: *anyopaque) void,
    };
    
    /// Parse assembly source into instructions
    pub fn parse(self: Self, source: []const u8, allocator: std.mem.Allocator) AssemblerError![]Instruction {
        return self.vtable.parse(self.ptr, source, allocator);
    }
    
    /// Encode instructions to machine code
    pub fn encode(self: Self, instructions: []Instruction, allocator: std.mem.Allocator) AssemblerError![]u8 {
        return self.vtable.encode(self.ptr, instructions, allocator);
    }
    
    /// Get register name by ID
    pub fn getRegisterName(self: Self, reg_id: u8, size: OperandSize) []const u8 {
        return self.vtable.getRegisterName(self.ptr, reg_id, size);
    }
    
    /// Get register ID by name
    pub fn getRegisterId(self: Self, name: []const u8) AssemblerError!u8 {
        return self.vtable.getRegisterId(self.ptr, name);
    }
    
    /// Clean up resources
    pub fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Helper to create an Assembler interface from a concrete type
pub fn assembler(impl: anytype) Assembler {
    const T = @TypeOf(impl.*);
    
    const gen = struct {
        fn parse(ptr: *anyopaque, source: []const u8, allocator: std.mem.Allocator) AssemblerError![]Instruction {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.parse(source, allocator);
        }
        
        fn encode(ptr: *anyopaque, instructions: []Instruction, allocator: std.mem.Allocator) AssemblerError![]u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.encode(instructions, allocator);
        }
        
        fn getRegisterName(ptr: *anyopaque, reg_id: u8, size: OperandSize) []const u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getRegisterName(reg_id, size);
        }
        
        fn getRegisterId(ptr: *anyopaque, name: []const u8) AssemblerError!u8 {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.getRegisterId(name);
        }
        
        fn deinit(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.deinit();
        }
        
        const vtable = Assembler.VTable{
            .parse = parse,
            .encode = encode,
            .getRegisterName = getRegisterName,
            .getRegisterId = getRegisterId,
            .deinit = deinit,
        };
    };
    
    return Assembler{
        .ptr = impl,
        .vtable = &gen.vtable,
    };
}
