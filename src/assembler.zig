//! Assembler Module
//!
//! Provides architecture-independent assembly support for HolyCross.
//! Currently supports:
//! - x64 (AMD64)
//!
//! Future architectures can be added by implementing the Assembler interface.

pub const assembler = @import("assembler/assembler.zig");
pub const x64 = @import("assembler/x64.zig");

// Re-export common types
pub const Assembler = assembler.Assembler;
pub const Instruction = assembler.Instruction;
pub const OperandType = assembler.OperandType;
pub const OperandSize = assembler.OperandSize;
pub const Label = assembler.Label;
pub const AssemblerError = assembler.AssemblerError;

// Re-export x64 specifically
pub const X64Assembler = x64.X64Assembler;
pub const X64Register = x64.Register;
