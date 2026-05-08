//! x64 Assembler
//!
//! Implements the Assembler interface for the x64 (AMD64) architecture.
//! Supports TempleOS-style assembly syntax with simplified mnemonics.

const std = @import("std");
const assembler = @import("assembler.zig");

const Assembler = assembler.Assembler;
const Instruction = assembler.Instruction;
const OperandType = assembler.OperandType;
const OperandSize = assembler.OperandSize;
const AssemblerError = assembler.AssemblerError;
const Label = assembler.Label;

/// x64 register encoding
pub const Register = enum(u8) {
    // 8-bit registers
    AL = 0, CL = 1, DL = 2, BL = 3,
    AH = 4, CH = 5, DH = 6, BH = 7,
    R8L = 8, R9L = 9, R10L = 10, R11L = 11,
    R12L = 12, R13L = 13, R14L = 14, R15L = 15,
    
    // 16-bit registers (offset by 16)
    AX = 16, CX = 17, DX = 18, BX = 19,
    SP = 20, BP = 21, SI = 22, DI = 23,
    R8W = 24, R9W = 25, R10W = 26, R11W = 27,
    R12W = 28, R13W = 29, R14W = 30, R15W = 31,
    
    // 32-bit registers (offset by 32)
    EAX = 32, ECX = 33, EDX = 34, EBX = 35,
    ESP = 36, EBP = 37, ESI = 38, EDI = 39,
    R8D = 40, R9D = 41, R10D = 42, R11D = 43,
    R12D = 44, R13D = 45, R14D = 46, R15D = 47,
    
    // 64-bit registers (offset by 48)
    RAX = 48, RCX = 49, RDX = 50, RBX = 51,
    RSP = 52, RBP = 53, RSI = 54, RDI = 55,
    R8 = 56, R9 = 57, R10 = 58, R11 = 59,
    R12 = 60, R13 = 61, R14 = 62, R15 = 63,
    
    // Special: RIP-relative addressing
    RIP = 255,
    
    pub fn fromString(name: []const u8) ?Register {
        // 64-bit registers
        if (std.mem.eql(u8, name, "RAX")) return .RAX;
        if (std.mem.eql(u8, name, "RCX")) return .RCX;
        if (std.mem.eql(u8, name, "RDX")) return .RDX;
        if (std.mem.eql(u8, name, "RBX")) return .RBX;
        if (std.mem.eql(u8, name, "RSP")) return .RSP;
        if (std.mem.eql(u8, name, "RBP")) return .RBP;
        if (std.mem.eql(u8, name, "RSI")) return .RSI;
        if (std.mem.eql(u8, name, "RDI")) return .RDI;
        if (std.mem.eql(u8, name, "R8")) return .R8;
        if (std.mem.eql(u8, name, "R9")) return .R9;
        if (std.mem.eql(u8, name, "R10")) return .R10;
        if (std.mem.eql(u8, name, "R11")) return .R11;
        if (std.mem.eql(u8, name, "R12")) return .R12;
        if (std.mem.eql(u8, name, "R13")) return .R13;
        if (std.mem.eql(u8, name, "R14")) return .R14;
        if (std.mem.eql(u8, name, "R15")) return .R15;
        
        // 32-bit registers
        if (std.mem.eql(u8, name, "EAX")) return .EAX;
        if (std.mem.eql(u8, name, "ECX")) return .ECX;
        if (std.mem.eql(u8, name, "EDX")) return .EDX;
        if (std.mem.eql(u8, name, "EBX")) return .EBX;
        if (std.mem.eql(u8, name, "ESP")) return .ESP;
        if (std.mem.eql(u8, name, "EBP")) return .EBP;
        if (std.mem.eql(u8, name, "ESI")) return .ESI;
        if (std.mem.eql(u8, name, "EDI")) return .EDI;
        
        // 16-bit registers
        if (std.mem.eql(u8, name, "AX")) return .AX;
        if (std.mem.eql(u8, name, "CX")) return .CX;
        if (std.mem.eql(u8, name, "DX")) return .DX;
        if (std.mem.eql(u8, name, "BX")) return .BX;
        if (std.mem.eql(u8, name, "SP")) return .SP;
        if (std.mem.eql(u8, name, "BP")) return .BP;
        if (std.mem.eql(u8, name, "SI")) return .SI;
        if (std.mem.eql(u8, name, "DI")) return .DI;
        
        // 8-bit registers
        if (std.mem.eql(u8, name, "AL")) return .AL;
        if (std.mem.eql(u8, name, "CL")) return .CL;
        if (std.mem.eql(u8, name, "DL")) return .DL;
        if (std.mem.eql(u8, name, "BL")) return .BL;
        if (std.mem.eql(u8, name, "AH")) return .AH;
        if (std.mem.eql(u8, name, "CH")) return .CH;
        if (std.mem.eql(u8, name, "DH")) return .DH;
        if (std.mem.eql(u8, name, "BH")) return .BH;
        
        return null;
    }
    
    pub fn getSize(self: Register) OperandSize {
        const val = @intFromEnum(self);
        if (val < 16) return .byte;
        if (val < 32) return .word;
        if (val < 48) return .dword;
        return .qword;
    }
    
    pub fn getHardwareId(self: Register) u8 {
        const val = @intFromEnum(self);
        return @intCast(val & 0xF);
    }
};

/// x64 Assembler implementation
pub const X64Assembler = struct {
    allocator: std.mem.Allocator,
    labels: std.StringHashMap(Label),
    
    pub fn init(allocator: std.mem.Allocator) X64Assembler {
        return .{
            .allocator = allocator,
            .labels = std.StringHashMap(Label).init(allocator),
        };
    }
    
    pub fn deinit(self: *X64Assembler) void {
        self.labels.deinit();
    }
    
    /// Parse assembly source into instructions
    pub fn parse(self: *X64Assembler, source: []const u8, allocator: std.mem.Allocator) AssemblerError![]Instruction {
        var instructions: std.ArrayList(Instruction) = .empty;
        errdefer instructions.deinit(allocator);
        
        var line_num: usize = 1;
        var lines = std.mem.splitScalar(u8, source, '\n');
        
        while (lines.next()) |line| : (line_num += 1) {
            const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
            
            // Skip empty lines and comments
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) {
                continue;
            }
            
            // Check for label definitions
            if (try self.parseLabel(trimmed, line_num)) {
                continue;
            }
            
            // Parse instruction
            if (try self.parseInstruction(trimmed, line_num, allocator)) |instr| {
                try instructions.append(allocator, instr);
            }
        }
        
        return instructions.toOwnedSlice(allocator);
    }
    
    /// Parse a label definition
    fn parseLabel(self: *X64Assembler, line: []const u8, line_num: usize) !bool {
        _ = line_num;
        
        // Check for local label (@@label:)
        if (std.mem.startsWith(u8, line, "@@")) {
            const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse return false;
            const label_name = std.mem.trim(u8, line[0..colon_idx], &std.ascii.whitespace);
            
            const label = Label{
                .name = label_name,
                .offset = 0, // Will be filled during encoding
                .is_exported = false,
                .is_local = true,
            };
            
            try self.labels.put(label_name, label);
            return true;
        }
        
        // Check for exported label (LABEL::)
        if (std.mem.indexOf(u8, line, "::")) |idx| {
            const label_name = std.mem.trim(u8, line[0..idx], &std.ascii.whitespace);
            
            const label = Label{
                .name = label_name,
                .offset = 0, // Will be filled during encoding
                .is_exported = true,
                .is_local = false,
            };
            
            try self.labels.put(label_name, label);
            return true;
        }
        
        // Check for regular label (LABEL:)
        if (std.mem.endsWith(u8, line, ":")) {
            const label_name = std.mem.trim(u8, line[0..line.len-1], &std.ascii.whitespace);
            
            // Skip if it contains whitespace (likely instruction)
            if (std.mem.indexOfAny(u8, label_name, &std.ascii.whitespace) != null) {
                return false;
            }
            
            const label = Label{
                .name = label_name,
                .offset = 0, // Will be filled during encoding
                .is_exported = false,
                .is_local = false,
            };
            
            try self.labels.put(label_name, label);
            return true;
        }
        
        return false;
    }
    
    /// Parse an instruction
    fn parseInstruction(self: *X64Assembler, line: []const u8, line_num: usize, allocator: std.mem.Allocator) !?Instruction {
        // Split on whitespace to get mnemonic
        var parts = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);
        const mnemonic = parts.next() orelse return null;
        
        // Skip data directives for now
        if (std.mem.eql(u8, mnemonic, "DU8") or 
            std.mem.eql(u8, mnemonic, "DU16") or
            std.mem.eql(u8, mnemonic, "DU32") or
            std.mem.eql(u8, mnemonic, "DU64")) {
            return null;
        }
        
        // Skip import directives
        if (std.mem.eql(u8, mnemonic, "IMPORT")) {
            return null;
        }
        
        // Get the rest of the line (operands)
        const rest_start = mnemonic.ptr + mnemonic.len - line.ptr;
        const operands_str = if (rest_start < line.len) 
            std.mem.trim(u8, line[rest_start..], &std.ascii.whitespace)
        else 
            "";
        
        // Parse operands
        var operands: std.ArrayList(OperandType) = .empty;
        errdefer operands.deinit(allocator);
        
        if (operands_str.len > 0) {
            try self.parseOperands(operands_str, &operands, allocator);
        }
        
        return Instruction{
            .mnemonic = mnemonic,
            .operands = try operands.toOwnedSlice(allocator),
            .location = .{
                .line = line_num,
                .column = 0,
            },
        };
    }
    
    /// Parse operands from a string
    fn parseOperands(self: *X64Assembler, operands_str: []const u8, operands: *std.ArrayList(OperandType), allocator: std.mem.Allocator) !void {
        
        // Split by comma
        var parts = std.mem.splitScalar(u8, operands_str, ',');
        
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;
            
            // Try to parse as register
            if (Register.fromString(trimmed)) |reg| {
                try operands.append(allocator, .{
                    .register = .{
                        .id = reg.getHardwareId(),
                        .size = reg.getSize(),
                    },
                });
                continue;
            }
            
            // Try to parse as immediate (number)
            if (self.parseImmediate(trimmed)) |imm| {
                try operands.append(allocator, imm);
                continue;
            }
            
            // Try to parse as memory operand
            if (std.mem.startsWith(u8, trimmed, "[") and std.mem.endsWith(u8, trimmed, "]")) {
                if (try self.parseMemoryOperand(trimmed)) |mem| {
                    try operands.append(allocator, mem);
                    continue;
                }
            }
            
            // Otherwise assume it's a label reference
            try operands.append(allocator, .{
                .label = .{
                    .name = trimmed,
                    .is_local = std.mem.startsWith(u8, trimmed, "@@"),
                },
            });
        }
    }
    
    /// Parse immediate value
    fn parseImmediate(self: *X64Assembler, text: []const u8) ?OperandType {
        _ = self;
        
        // Try hexadecimal (0x prefix)
        if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
            const value = std.fmt.parseInt(i64, text[2..], 16) catch return null;
            return .{
                .immediate = .{
                    .value = value,
                    .size = .qword, // Default to qword
                },
            };
        }
        
        // Try decimal
        const value = std.fmt.parseInt(i64, text, 10) catch return null;
        
        // Determine size based on value
        const size: OperandSize = if (value >= -128 and value <= 127)
            .byte
        else if (value >= -32768 and value <= 32767)
            .word
        else if (value >= -2147483648 and value <= 2147483647)
            .dword
        else
            .qword;
        
        return .{
            .immediate = .{
                .value = value,
                .size = size,
            },
        };
    }
    
    /// Parse memory operand like [RBP+8] or [RAX*4+RBX]
    fn parseMemoryOperand(self: *X64Assembler, text: []const u8) !?OperandType {
        _ = self;
        
        // Remove brackets
        const inner = std.mem.trim(u8, text[1..text.len-1], &std.ascii.whitespace);
        
        // For now, simple implementation: just base register or base+displacement
        var base_reg: ?u8 = null;
        var displacement: i32 = 0;
        
        // Check for + or -
        if (std.mem.indexOfAny(u8, inner, "+-")) |op_idx| {
            const base_str = std.mem.trim(u8, inner[0..op_idx], &std.ascii.whitespace);
            const disp_str = std.mem.trim(u8, inner[op_idx..], &std.ascii.whitespace);
            
            // Parse base register
            if (Register.fromString(base_str)) |reg| {
                base_reg = reg.getHardwareId();
            }
            
            // Parse displacement
            displacement = std.fmt.parseInt(i32, disp_str, 10) catch 0;
        } else {
            // Just a register
            if (Register.fromString(inner)) |reg| {
                base_reg = reg.getHardwareId();
            }
        }
        
        return .{
            .memory = .{
                .base = base_reg,
                .index = null,
                .scale = 1,
                .displacement = displacement,
                .size = .qword,
                .segment = null,
            },
        };
    }
    
    /// Encode instructions to machine code
    pub fn encode(self: *X64Assembler, instructions: []Instruction, allocator: std.mem.Allocator) AssemblerError![]u8 {
        var code: std.ArrayList(u8) = .empty;
        errdefer code.deinit(allocator);
        
        for (instructions) |instr| {
            try self.encodeInstruction(instr, &code, allocator);
        }
        
        return code.toOwnedSlice(allocator);
    }
    
    /// Helper: Encode arithmetic/logical operations (ADD, SUB, AND, OR, XOR, CMP, TEST)
    fn encodeArithmeticLogical(mnemonic: []const u8, instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
        const opcode_map = std.StaticStringMap(u8).initComptime(.{
            .{ "ADD", 0x00 }, // ADD: base opcode 0x00-0x05
            .{ "OR",  0x08 }, // OR:  base opcode 0x08-0x0D
            .{ "ADC", 0x10 }, // ADC: base opcode 0x10-0x15
            .{ "SBB", 0x18 }, // SBB: base opcode 0x18-0x1D
            .{ "AND", 0x20 }, // AND: base opcode 0x20-0x25
            .{ "SUB", 0x28 }, // SUB: base opcode 0x28-0x2D
            .{ "XOR", 0x30 }, // XOR: base opcode 0x30-0x35
            .{ "CMP", 0x38 }, // CMP: base opcode 0x38-0x3D
        });
        
        const base_opcode = opcode_map.get(mnemonic) orelse return false;
        
        if (instr.operands.len == 2) {
            const dest = instr.operands[0];
            const src = instr.operands[1];
            
            // reg, imm form
            if (dest == .register and src == .immediate) {
                const reg = dest.register;
                const imm = src.immediate;
                
                if (reg.size == .qword) {
                    var rex: u8 = 0x48;
                    if (reg.id >= 8) rex |= 0x01;
                    try code.append(allocator, rex);
                    
                    if (imm.size == .byte) {
                        // op r64, imm8: REX.W + 0x83 /<digit> + imm8
                        try code.append(allocator, 0x83);
                        const digit = base_opcode >> 3; // Extract digit from base opcode
                        try code.append(allocator, 0xC0 + (digit << 3) + (reg.id & 0x7));
                        try code.append(allocator, @bitCast(@as(i8, @intCast(imm.value))));
                    } else {
                        // op r64, imm32: REX.W + 0x81 /<digit> + imm32
                        try code.append(allocator, 0x81);
                        const digit = base_opcode >> 3;
                        try code.append(allocator, 0xC0 + (digit << 3) + (reg.id & 0x7));
                        const val: i32 = @intCast(imm.value);
                        const bytes = std.mem.toBytes(val);
                        try code.appendSlice(allocator, &bytes);
                    }
                }
                return true;
            }
            
            // reg, reg form
            if (dest == .register and src == .register) {
                const dst_reg = dest.register;
                const src_reg = src.register;
                
                if (dst_reg.size == .qword and src_reg.size == .qword) {
                    var rex: u8 = 0x48;
                    if (dst_reg.id >= 8) rex |= 0x01; // REX.B
                    if (src_reg.id >= 8) rex |= 0x04; // REX.R
                    try code.append(allocator, rex);
                    
                    // op r64, r64: base+1 + ModR/M
                    try code.append(allocator, base_opcode + 0x01);
                    const modrm = 0xC0 | ((src_reg.id & 0x7) << 3) | (dst_reg.id & 0x7);
                    try code.append(allocator, modrm);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /// Helper: Encode TEST instruction
    fn encodeTest(instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
        if (instr.operands.len == 2) {
            const dest = instr.operands[0];
            const src = instr.operands[1];
            
            // TEST reg, reg
            if (dest == .register and src == .register) {
                const dst_reg = dest.register;
                const src_reg = src.register;
                
                if (dst_reg.size == .qword and src_reg.size == .qword) {
                    var rex: u8 = 0x48;
                    if (dst_reg.id >= 8) rex |= 0x01;
                    if (src_reg.id >= 8) rex |= 0x04;
                    try code.append(allocator, rex);
                    try code.append(allocator, 0x85); // TEST r64, r64
                    const modrm = 0xC0 | ((src_reg.id & 0x7) << 3) | (dst_reg.id & 0x7);
                    try code.append(allocator, modrm);
                    return true;
                }
            }
            
            // TEST reg, imm
            if (dest == .register and src == .immediate) {
                const reg = dest.register;
                const imm = src.immediate;
                
                if (reg.size == .qword) {
                    var rex: u8 = 0x48;
                    if (reg.id >= 8) rex |= 0x01;
                    try code.append(allocator, rex);
                    
                    // TEST r64, imm32: REX.W + 0xF7 /0 + imm32
                    try code.append(allocator, 0xF7);
                    try code.append(allocator, 0xC0 + (reg.id & 0x7));
                    const val: i32 = @intCast(imm.value);
                    const bytes = std.mem.toBytes(val);
                    try code.appendSlice(allocator, &bytes);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    /// Helper: Encode unary operations (NEG, NOT, INC, DEC)
    fn encodeUnaryOp(mnemonic: []const u8, instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
        if (instr.operands.len != 1) return false;
        if (instr.operands[0] != .register) return false;
        
        const reg = instr.operands[0].register;
        if (reg.size != .qword) return false;
        
        var rex: u8 = 0x48;
        if (reg.id >= 8) rex |= 0x01;
        try code.append(allocator, rex);
        
        if (std.mem.eql(u8, mnemonic, "NEG")) {
            try code.append(allocator, 0xF7);
            try code.append(allocator, 0xD8 + (reg.id & 0x7)); // /3
            return true;
        } else if (std.mem.eql(u8, mnemonic, "NOT")) {
            try code.append(allocator, 0xF7);
            try code.append(allocator, 0xD0 + (reg.id & 0x7)); // /2
            return true;
        } else if (std.mem.eql(u8, mnemonic, "INC")) {
            try code.append(allocator, 0xFF);
            try code.append(allocator, 0xC0 + (reg.id & 0x7)); // /0
            return true;
        } else if (std.mem.eql(u8, mnemonic, "DEC")) {
            try code.append(allocator, 0xFF);
            try code.append(allocator, 0xC8 + (reg.id & 0x7)); // /1
            return true;
        }
        
        return false;
    }
    
    /// Helper: Encode shift/rotate operations
    fn encodeShiftRotate(mnemonic: []const u8, instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
        const opcode_map = std.StaticStringMap(u8).initComptime(.{
            .{ "ROL", 0 },
            .{ "ROR", 1 },
            .{ "RCL", 2 },
            .{ "RCR", 3 },
            .{ "SHL", 4 },
            .{ "SHR", 5 },
            .{ "SAR", 7 },
        });
        
        const digit = opcode_map.get(mnemonic) orelse return false;
        
        if (instr.operands.len != 2) return false;
        if (instr.operands[0] != .register) return false;
        
        const reg = instr.operands[0].register;
        if (reg.size != .qword) return false;
        
        var rex: u8 = 0x48;
        if (reg.id >= 8) rex |= 0x01;
        try code.append(allocator, rex);
        
        // Shift by CL
        if (instr.operands[1] == .register and instr.operands[1].register.id == 1) { // CL
            try code.append(allocator, 0xD3); // Shift r64, CL
            try code.append(allocator, 0xC0 + (digit << 3) + (reg.id & 0x7));
            return true;
        }
        
        // Shift by immediate
        if (instr.operands[1] == .immediate) {
            const imm = instr.operands[1].immediate;
            if (imm.value == 1) {
                try code.append(allocator, 0xD1); // Shift r64, 1
            } else {
                try code.append(allocator, 0xC1); // Shift r64, imm8
            }
            try code.append(allocator, 0xC0 + (digit << 3) + (reg.id & 0x7));
            if (imm.value != 1) {
                try code.append(allocator, @intCast(imm.value));
            }
            return true;
        }
        
        return false;
    }
    
    /// Helper: Encode multiplication and division
    fn encodeMulDiv(mnemonic: []const u8, instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
        if (instr.operands.len != 1) return false;
        if (instr.operands[0] != .register) return false;
        
        const reg = instr.operands[0].register;
        if (reg.size != .qword) return false;
        
        var rex: u8 = 0x48;
        if (reg.id >= 8) rex |= 0x01;
        try code.append(allocator, rex);
        
        if (std.mem.eql(u8, mnemonic, "MUL")) {
            try code.append(allocator, 0xF7);
            try code.append(allocator, 0xE0 + (reg.id & 0x7)); // /4
            return true;
        } else if (std.mem.eql(u8, mnemonic, "IMUL")) {
            try code.append(allocator, 0xF7);
            try code.append(allocator, 0xE8 + (reg.id & 0x7)); // /5
            return true;
        } else if (std.mem.eql(u8, mnemonic, "DIV")) {
            try code.append(allocator, 0xF7);
            try code.append(allocator, 0xF0 + (reg.id & 0x7)); // /6
            return true;
        } else if (std.mem.eql(u8, mnemonic, "IDIV")) {
            try code.append(allocator, 0xF7);
            try code.append(allocator, 0xF8 + (reg.id & 0x7)); // /7
            return true;
        }
        
        return false;
    }
    
    /// Helper: Encode jump instructions
    fn encodeJump(mnemonic: []const u8, instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
        const jump_map = std.StaticStringMap(u8).initComptime(.{
            .{ "JO",   0x70 }, .{ "JNO",  0x71 },
            .{ "JB",   0x72 }, .{ "JAE",  0x73 },
            .{ "JE",   0x74 }, .{ "JNE",  0x75 },
            .{ "JBE",  0x76 }, .{ "JA",   0x77 },
            .{ "JS",   0x78 }, .{ "JNS",  0x79 },
            .{ "JP",   0x7A }, .{ "JNP",  0x7B },
            .{ "JL",   0x7C }, .{ "JGE",  0x7D },
            .{ "JLE",  0x7E }, .{ "JG",   0x7F },
            .{ "JZ",   0x74 }, // alias for JE
            .{ "JNZ",  0x75 }, // alias for JNE
            .{ "JC",   0x72 }, // alias for JB
            .{ "JNC",  0x73 }, // alias for JAE
        });
        
        if (std.mem.eql(u8, mnemonic, "JMP")) {
            if (instr.operands.len == 1) {
                if (instr.operands[0] == .label) {
                    // JMP rel32: 0xE9 + rel32
                    try code.append(allocator, 0xE9);
                    try code.append(allocator, 0x00);
                    try code.append(allocator, 0x00);
                    try code.append(allocator, 0x00);
                    try code.append(allocator, 0x00);
                    return true;
                }
                if (instr.operands[0] == .register) {
                    const reg = instr.operands[0].register;
                    if (reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (reg.id >= 8) rex |= 0x01;
                        try code.append(allocator, rex);
                        try code.append(allocator, 0xFF);
                        try code.append(allocator, 0xE0 + (reg.id & 0x7)); // /4
                        return true;
                    }
                }
            }
            return true;
        }
        
        const opcode = jump_map.get(mnemonic) orelse return false;
        
        if (instr.operands.len == 1 and instr.operands[0] == .label) {
            // Conditional jump short: opcode + rel8
            try code.append(allocator, opcode);
            try code.append(allocator, 0x00); // Placeholder
            return true;
        }
        
        return false;
    }
    
    /// Helper: Encode data movement instructions
    fn encodeDataMovement(mnemonic: []const u8, instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
        if (std.mem.eql(u8, mnemonic, "LEA")) {
            // LEA r64, [...]
            // Simplified - just return false for now since we need memory operand support
            return false;
        }
        
        if (std.mem.eql(u8, mnemonic, "XCHG")) {
            if (instr.operands.len == 2) {
                if (instr.operands[0] == .register and instr.operands[1] == .register) {
                    const reg1 = instr.operands[0].register;
                    const reg2 = instr.operands[1].register;
                    
                    if (reg1.size == .qword and reg2.size == .qword) {
                        var rex: u8 = 0x48;
                        if (reg1.id >= 8) rex |= 0x01;
                        if (reg2.id >= 8) rex |= 0x04;
                        try code.append(allocator, rex);
                        try code.append(allocator, 0x87); // XCHG r64, r64
                        const modrm = 0xC0 | ((reg2.id & 0x7) << 3) | (reg1.id & 0x7);
                        try code.append(allocator, modrm);
                        return true;
                    }
                }
            }
        }
        
        // MOVZX and MOVSX need more complex encoding - skip for now
        
        return false;
    }

    /// Encode a single instruction to machine code
    fn encodeInstruction(self: *X64Assembler, instr: Instruction, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        _ = self;
        
        const mnemonic = instr.mnemonic;
        
        // Simple encoding for basic instructions
        // This is a simplified implementation - full x64 encoding is complex
        
        // PUSH reg64
        if (std.mem.eql(u8, mnemonic, "PUSH")) {
            if (instr.operands.len == 1) {
                switch (instr.operands[0]) {
                    .register => |reg| {
                        if (reg.size == .qword) {
                            // PUSH reg: 0x50 + reg_id (0-7) or REX.B + 0x50 + reg_id (8-15)
                            if (reg.id >= 8) {
                                try code.append(allocator, 0x41); // REX.B prefix
                                try code.append(allocator, 0x50 + (reg.id - 8));
                            } else {
                                try code.append(allocator, 0x50 + reg.id);
                            }
                        }
                    },
                    .immediate => |imm| {
                        // PUSH imm32: 0x68 + imm32
                        if (imm.size == .byte) {
                            try code.append(allocator, 0x6A); // PUSH imm8
                            try code.append(allocator, @bitCast(@as(i8, @intCast(imm.value))));
                        } else {
                            try code.append(allocator, 0x68); // PUSH imm32
                            const bytes = std.mem.toBytes(@as(i32, @intCast(imm.value)));
                            try code.appendSlice(allocator, &bytes);
                        }
                    },
                    else => return error.InvalidOperand,
                }
            }
        }
        
        // POP reg64
        else if (std.mem.eql(u8, mnemonic, "POP")) {
            if (instr.operands.len == 1) {
                switch (instr.operands[0]) {
                    .register => |reg| {
                        if (reg.size == .qword) {
                            // POP reg: 0x58 + reg_id
                            if (reg.id >= 8) {
                                try code.append(allocator, 0x41); // REX.B prefix
                                try code.append(allocator, 0x58 + (reg.id - 8));
                            } else {
                                try code.append(allocator, 0x58 + reg.id);
                            }
                        }
                    },
                    else => return error.InvalidOperand,
                }
            }
        }
        
        // RET
        else if (std.mem.eql(u8, mnemonic, "RET")) {
            try code.append(allocator, 0xC3); // Near return
        }
        
        // RET imm16 (like TempleOS RET1)
        else if (std.mem.eql(u8, mnemonic, "RET1")) {
            if (instr.operands.len == 1) {
                switch (instr.operands[0]) {
                    .immediate => |imm| {
                        try code.append(allocator, 0xC2); // RET imm16
                        const val: u16 = @intCast(imm.value);
                        const bytes = std.mem.toBytes(val);
                        try code.appendSlice(allocator, &bytes);
                    },
                    else => return error.InvalidOperand,
                }
            }
        }
        
        // CALL (simplified - only label for now)
        else if (std.mem.eql(u8, mnemonic, "CALL")) {
            if (instr.operands.len == 1) {
                switch (instr.operands[0]) {
                    .label => {
                        // CALL rel32: 0xE8 + rel32
                        // For now, emit placeholder - will need proper label resolution
                        try code.append(allocator, 0xE8);
                        try code.append(allocator, 0x00);
                        try code.append(allocator, 0x00);
                        try code.append(allocator, 0x00);
                        try code.append(allocator, 0x00);
                    },
                    .register => |reg| {
                        // CALL reg: 0xFF /2
                        if (reg.size == .qword) {
                            if (reg.id >= 8) {
                                try code.append(allocator, 0x41); // REX.B
                            }
                            try code.append(allocator, 0xFF);
                            try code.append(allocator, 0xD0 + (reg.id & 0x7)); // ModRM: 11 010 reg
                        }
                    },
                    else => return error.InvalidOperand,
                }
            }
        }
        
        // MOV (simplified - only reg,reg and reg,imm for now)
        else if (std.mem.eql(u8, mnemonic, "MOV")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                switch (dest) {
                    .register => |dst_reg| {
                        switch (src) {
                            // MOV reg, reg
                            .register => |src_reg| {
                                if (dst_reg.size == .qword and src_reg.size == .qword) {
                                    // REX.W prefix
                                    var rex: u8 = 0x48;
                                    if (dst_reg.id >= 8) rex |= 0x01; // REX.B
                                    if (src_reg.id >= 8) rex |= 0x04; // REX.R
                                    try code.append(allocator, rex);
                                    
                                    // MOV r64, r64: 0x89 ModR/M
                                    try code.append(allocator, 0x89);
                                    const modrm = 0xC0 | ((src_reg.id & 0x7) << 3) | (dst_reg.id & 0x7);
                                    try code.append(allocator, modrm);
                                }
                            },
                            
                            // MOV reg, imm
                            .immediate => |imm| {
                                if (dst_reg.size == .qword) {
                                    // MOV r64, imm64: REX.W + 0xB8+reg + imm64
                                    var rex: u8 = 0x48;
                                    if (dst_reg.id >= 8) rex |= 0x01; // REX.B
                                    try code.append(allocator, rex);
                                    try code.append(allocator, 0xB8 + (dst_reg.id & 0x7));
                                    
                                    const bytes = std.mem.toBytes(imm.value);
                                    try code.appendSlice(allocator, &bytes);
                                } else if (dst_reg.size == .dword) {
                                    // MOV r32, imm32: 0xB8+reg + imm32
                                    if (dst_reg.id >= 8) {
                                        try code.append(allocator, 0x41); // REX.B
                                    }
                                    try code.append(allocator, 0xB8 + (dst_reg.id & 0x7));
                                    const val: i32 = @intCast(imm.value);
                                    const bytes = std.mem.toBytes(val);
                                    try code.appendSlice(allocator, &bytes);
                                }
                            },
                            
                            else => return error.InvalidOperand,
                        }
                    },
                    else => return error.InvalidOperand,
                }
            }
        }
        
        // Arithmetic and logical operations (ADD, SUB, AND, OR, XOR, CMP, TEST)
        else if (try encodeArithmeticLogical(mnemonic, instr, code, allocator)) {
            // Handled
        }
        
        // SUB (handled by encodeArithmeticLogical)
        // AND (handled by encodeArithmeticLogical)
        // OR (handled by encodeArithmeticLogical)
        // XOR (handled by encodeArithmeticLogical)
        // CMP (handled by encodeArithmeticLogical)
        // TEST (handled by encodeArithmeticLogical)
        
        // Unary operations (NEG, NOT, INC, DEC)
        else if (try encodeUnaryOp(mnemonic, instr, code, allocator)) {
            // Handled
        }
        
        // Shift/rotate operations (SHL, SHR, SAR, ROL, ROR, RCL, RCR)
        else if (try encodeShiftRotate(mnemonic, instr, code, allocator)) {
            // Handled
        }
        
        // Multiplication and division (MUL, IMUL, DIV, IDIV)
        else if (try encodeMulDiv(mnemonic, instr, code, allocator)) {
            // Handled
        }
        
        // Jump instructions
        else if (try encodeJump(mnemonic, instr, code, allocator)) {
            // Handled
        }
        
        // Data movement (LEA, XCHG, MOVZX, MOVSX)
        else if (try encodeDataMovement(mnemonic, instr, code, allocator)) {
            // Handled
        }
        
        // NOP
        else if (std.mem.eql(u8, mnemonic, "NOP")) {
            try code.append(allocator, 0x90);
        }
        
        // LOOP rel8
        else if (std.mem.eql(u8, mnemonic, "LOOP")) {
            try code.append(allocator, 0xE2);
            // Placeholder for relative offset
            try code.append(allocator, 0x00);
        }
        
        // LEAVE - High-level procedure exit (C9)
        else if (std.mem.eql(u8, mnemonic, "LEAVE")) {
            try code.append(allocator, 0xC9);
        }
        
        // MOVSX - Move with sign extension
        else if (std.mem.eql(u8, mnemonic, "MOVSX")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .register) {
                    const dst_reg = dest.register;
                    const src_reg = src.register;
                    
                    // MOVSX r64, r8: REX.W + 0x0F 0xBE
                    // MOVSX r64, r16: REX.W + 0x0F 0xBF
                    // MOVSX r64, r32: REX.W + 0x63 (MOVSXD)
                    if (dst_reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (dst_reg.id >= 8) rex |= 0x04; // REX.R
                        if (src_reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        
                        if (src_reg.size == .byte) {
                            try code.append(allocator, 0x0F);
                            try code.append(allocator, 0xBE);
                        } else if (src_reg.size == .word) {
                            try code.append(allocator, 0x0F);
                            try code.append(allocator, 0xBF);
                        } else if (src_reg.size == .dword) {
                            try code.append(allocator, 0x63); // MOVSXD
                        }
                        
                        const modrm = 0xC0 | ((dst_reg.id & 0x7) << 3) | (src_reg.id & 0x7);
                        try code.append(allocator, modrm);
                    }
                }
            }
        }
        
        // MOVZX - Move with zero extension
        else if (std.mem.eql(u8, mnemonic, "MOVZX")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .register) {
                    const dst_reg = dest.register;
                    const src_reg = src.register;
                    
                    // MOVZX r64, r8: REX.W + 0x0F 0xB6
                    // MOVZX r64, r16: REX.W + 0x0F 0xB7
                    if (dst_reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (dst_reg.id >= 8) rex |= 0x04; // REX.R
                        if (src_reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        
                        try code.append(allocator, 0x0F);
                        if (src_reg.size == .byte) {
                            try code.append(allocator, 0xB6);
                        } else if (src_reg.size == .word) {
                            try code.append(allocator, 0xB7);
                        }
                        
                        const modrm = 0xC0 | ((dst_reg.id & 0x7) << 3) | (src_reg.id & 0x7);
                        try code.append(allocator, modrm);
                    }
                }
            }
        }
        
        // SETcc - Set byte on condition
        else if (std.mem.startsWith(u8, mnemonic, "SET")) {
            const condition_code_map = std.StaticStringMap(u8).initComptime(.{
                .{ "SETO",   0x90 }, .{ "SETNO",  0x91 },
                .{ "SETB",   0x92 }, .{ "SETAE",  0x93 },
                .{ "SETE",   0x94 }, .{ "SETNE",  0x95 },
                .{ "SETBE",  0x96 }, .{ "SETA",   0x97 },
                .{ "SETS",   0x98 }, .{ "SETNS",  0x99 },
                .{ "SETP",   0x9A }, .{ "SETNP",  0x9B },
                .{ "SETL",   0x9C }, .{ "SETGE",  0x9D },
                .{ "SETLE",  0x9E }, .{ "SETG",   0x9F },
                .{ "SETZ",   0x94 }, // alias for SETE
            });
            
            if (condition_code_map.get(mnemonic)) |opcode| {
                if (instr.operands.len == 1 and instr.operands[0] == .register) {
                    const reg = instr.operands[0].register;
                    if (reg.size == .byte) {
                        // SETcc r8: 0x0F <opcode> ModRM
                        if (reg.id >= 8) {
                            try code.append(allocator, 0x41); // REX.B for R8L-R15L
                        }
                        try code.append(allocator, 0x0F);
                        try code.append(allocator, opcode);
                        const modrm = 0xC0 | (reg.id & 0x7);
                        try code.append(allocator, modrm);
                    }
                }
            }
        }
        
        // Bit manipulation instructions
        // BSF - Bit scan forward
        else if (std.mem.eql(u8, mnemonic, "BSF")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .register) {
                    const dst_reg = dest.register;
                    const src_reg = src.register;
                    
                    if (dst_reg.size == .qword and src_reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (dst_reg.id >= 8) rex |= 0x04; // REX.R
                        if (src_reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        try code.append(allocator, 0x0F);
                        try code.append(allocator, 0xBC); // BSF opcode
                        const modrm = 0xC0 | ((dst_reg.id & 0x7) << 3) | (src_reg.id & 0x7);
                        try code.append(allocator, modrm);
                    }
                }
            }
        }
        
        // BSR - Bit scan reverse
        else if (std.mem.eql(u8, mnemonic, "BSR")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .register) {
                    const dst_reg = dest.register;
                    const src_reg = src.register;
                    
                    if (dst_reg.size == .qword and src_reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (dst_reg.id >= 8) rex |= 0x04; // REX.R
                        if (src_reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        try code.append(allocator, 0x0F);
                        try code.append(allocator, 0xBD); // BSR opcode
                        const modrm = 0xC0 | ((dst_reg.id & 0x7) << 3) | (src_reg.id & 0x7);
                        try code.append(allocator, modrm);
                    }
                }
            }
        }
        
        // BT - Bit test
        else if (std.mem.eql(u8, mnemonic, "BT")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .immediate) {
                    const reg = dest.register;
                    const imm = src.immediate;
                    
                    if (reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        try code.append(allocator, 0x0F);
                        try code.append(allocator, 0xBA); // BT r64, imm8 opcode
                        const modrm = 0xE0 | (reg.id & 0x7); // /4
                        try code.append(allocator, modrm);
                        try code.append(allocator, @bitCast(@as(i8, @intCast(imm.value))));
                    }
                }
            }
        }
        
        // BTC - Bit test and complement
        else if (std.mem.eql(u8, mnemonic, "BTC")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .immediate) {
                    const reg = dest.register;
                    const imm = src.immediate;
                    
                    if (reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        try code.append(allocator, 0x0F);
                        try code.append(allocator, 0xBA); // BTC r64, imm8 opcode
                        const modrm = 0xF8 | (reg.id & 0x7); // /7
                        try code.append(allocator, modrm);
                        try code.append(allocator, @bitCast(@as(i8, @intCast(imm.value))));
                    }
                }
            }
        }
        
        // BTR - Bit test and reset
        else if (std.mem.eql(u8, mnemonic, "BTR")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .immediate) {
                    const reg = dest.register;
                    const imm = src.immediate;
                    
                    if (reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        try code.append(allocator, 0x0F);
                        try code.append(allocator, 0xBA); // BTR r64, imm8 opcode
                        const modrm = 0xF0 | (reg.id & 0x7); // /6
                        try code.append(allocator, modrm);
                        try code.append(allocator, @bitCast(@as(i8, @intCast(imm.value))));
                    }
                }
            }
        }
        
        // BTS - Bit test and set
        else if (std.mem.eql(u8, mnemonic, "BTS")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                if (dest == .register and src == .immediate) {
                    const reg = dest.register;
                    const imm = src.immediate;
                    
                    if (reg.size == .qword) {
                        var rex: u8 = 0x48;
                        if (reg.id >= 8) rex |= 0x01; // REX.B
                        try code.append(allocator, rex);
                        try code.append(allocator, 0x0F);
                        try code.append(allocator, 0xBA); // BTS r64, imm8 opcode
                        const modrm = 0xE8 | (reg.id & 0x7); // /5
                        try code.append(allocator, modrm);
                        try code.append(allocator, @bitCast(@as(i8, @intCast(imm.value))));
                    }
                }
            }
        }
        
        // BSWAP - Byte swap
        else if (std.mem.eql(u8, mnemonic, "BSWAP")) {
            if (instr.operands.len == 1 and instr.operands[0] == .register) {
                const reg = instr.operands[0].register;
                
                if (reg.size == .qword) {
                    var rex: u8 = 0x48;
                    if (reg.id >= 8) rex |= 0x01; // REX.B
                    try code.append(allocator, rex);
                    try code.append(allocator, 0x0F);
                    try code.append(allocator, 0xC8 + (reg.id & 0x7)); // BSWAP r64
                } else if (reg.size == .dword) {
                    if (reg.id >= 8) {
                        try code.append(allocator, 0x41); // REX.B
                    }
                    try code.append(allocator, 0x0F);
                    try code.append(allocator, 0xC8 + (reg.id & 0x7)); // BSWAP r32
                }
            }
        }
        
        // For unknown instructions, skip for now
        else {
            // Just emit a NOP as placeholder
            try code.append(allocator, 0x90);
        }
    }
    
    /// Get register name by ID and size
    pub fn getRegisterName(self: *X64Assembler, reg_id: u8, size: OperandSize) []const u8 {
        _ = self;
        
        return switch (size) {
            .qword => switch (reg_id) {
                0 => "RAX", 1 => "RCX", 2 => "RDX", 3 => "RBX",
                4 => "RSP", 5 => "RBP", 6 => "RSI", 7 => "RDI",
                8 => "R8", 9 => "R9", 10 => "R10", 11 => "R11",
                12 => "R12", 13 => "R13", 14 => "R14", 15 => "R15",
                else => "???",
            },
            .dword => switch (reg_id) {
                0 => "EAX", 1 => "ECX", 2 => "EDX", 3 => "EBX",
                4 => "ESP", 5 => "EBP", 6 => "ESI", 7 => "EDI",
                8 => "R8D", 9 => "R9D", 10 => "R10D", 11 => "R11D",
                12 => "R12D", 13 => "R13D", 14 => "R14D", 15 => "R15D",
                else => "???",
            },
            .word => switch (reg_id) {
                0 => "AX", 1 => "CX", 2 => "DX", 3 => "BX",
                4 => "SP", 5 => "BP", 6 => "SI", 7 => "DI",
                8 => "R8W", 9 => "R9W", 10 => "R10W", 11 => "R11W",
                12 => "R12W", 13 => "R13W", 14 => "R14W", 15 => "R15W",
                else => "???",
            },
            .byte => switch (reg_id) {
                0 => "AL", 1 => "CL", 2 => "DL", 3 => "BL",
                4 => "AH", 5 => "CH", 6 => "DH", 7 => "BH",
                8 => "R8L", 9 => "R9L", 10 => "R10L", 11 => "R11L",
                12 => "R12L", 13 => "R13L", 14 => "R14L", 15 => "R15L",
                else => "???",
            },
        };
    }
    
    /// Get register ID by name
    pub fn getRegisterId(self: *X64Assembler, name: []const u8) AssemblerError!u8 {
        _ = self;
        
        const reg = Register.fromString(name) orelse return error.InvalidRegister;
        return reg.getHardwareId();
    }
    
    /// Create an Assembler interface from this x64 assembler
    pub fn asAssembler(self: *X64Assembler) Assembler {
        return assembler.assembler(self);
    }
};
