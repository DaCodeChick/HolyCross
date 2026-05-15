//! x64 Assembler
//!
//! Implements the Assembler interface for the x64 (AMD64) architecture.
//! Supports TempleOS-style assembly syntax with simplified mnemonics.

const std = @import("std");
const assembler = @import("assembler.zig");
const expr_eval = @import("expr_eval.zig");

const Assembler = assembler.Assembler;
const Instruction = assembler.Instruction;
const OperandType = assembler.OperandType;
const OperandSize = assembler.OperandSize;
const AssemblerError = assembler.AssemblerError;
const Label = assembler.Label;
const EvalContext = expr_eval.EvalContext;

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
    expr_ctx: EvalContext,
    
    pub fn init(allocator: std.mem.Allocator) X64Assembler {
        return .{
            .allocator = allocator,
            .labels = std.StringHashMap(Label).init(allocator),
            .expr_ctx = EvalContext.init(allocator),
        };
    }
    
    /// Initialize with type layout information for expression evaluation
    pub fn initWithTypes(
        allocator: std.mem.Allocator,
        type_layouts: *const std.StringHashMap(expr_eval.TypeLayout),
    ) X64Assembler {
        return .{
            .allocator = allocator,
            .labels = std.StringHashMap(Label).init(allocator),
            .expr_ctx = expr_eval.EvalContext{
                .allocator = allocator,
                .symbol_table = null,
                .type_layouts = type_layouts,
                .constants = std.StringHashMap(i64).init(allocator),
            },
        };
    }
    
    pub fn deinit(self: *X64Assembler) void {
        self.labels.deinit();
        self.expr_ctx.deinit();
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
            
            // Check for label definitions - track the instruction index they mark
            if (try self.parseLabelAtIndex(trimmed, line_num, instructions.items.len)) {
                continue;
            }
            
            // Parse instruction
            if (try self.parseInstruction(trimmed, line_num, allocator)) |instr| {
                try instructions.append(allocator, instr);
            }
        }
        
        return instructions.toOwnedSlice(allocator);
    }
    
    /// Parse a label definition and track its instruction index
    fn parseLabelAtIndex(self: *X64Assembler, line: []const u8, line_num: usize, instr_idx: usize) !bool {
        _ = line_num;
        
        // Check for local label (@@label:)
        if (std.mem.startsWith(u8, line, "@@")) {
            const colon_idx = std.mem.indexOfScalar(u8, line, ':') orelse return false;
            const label_name = std.mem.trim(u8, line[0..colon_idx], &std.ascii.whitespace);
            
            const label = Label{
                .name = label_name,
                .offset = instr_idx, // Store instruction index for now
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
                .offset = instr_idx, // Store instruction index for now
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
                .offset = instr_idx, // Store instruction index for now
                .is_exported = false,
                .is_local = false,
            };
            
            try self.labels.put(label_name, label);
            return true;
        }
        
        return false;
    }
    
    /// Parse a label definition
    /// Parse an instruction or directive
    fn parseInstruction(self: *X64Assembler, line: []const u8, line_num: usize, allocator: std.mem.Allocator) !?Instruction {
        // Split on whitespace to get mnemonic
        var parts = std.mem.tokenizeAny(u8, line, &std.ascii.whitespace);
        const mnemonic = parts.next() orelse return null;
        
        // Check for data directives (DU8, DU16, DU32, DU64)
        if (std.mem.eql(u8, mnemonic, "DU8") or 
            std.mem.eql(u8, mnemonic, "DU16") or
            std.mem.eql(u8, mnemonic, "DU32") or
            std.mem.eql(u8, mnemonic, "DU64")) {
            return try self.parseDataDirective(line, mnemonic, line_num, allocator);
        }
        
        // Check for IMPORT directive
        if (std.mem.eql(u8, mnemonic, "IMPORT")) {
            return try self.parseImportDirective(line, line_num, allocator);
        }
        
        // Check for USE directives
        if (std.mem.eql(u8, mnemonic, "USE16") or
            std.mem.eql(u8, mnemonic, "USE32") or
            std.mem.eql(u8, mnemonic, "USE64")) {
            return try self.parseUseDirective(mnemonic, line_num);
        }
        
        // Check for ALIGN directive
        if (std.mem.eql(u8, mnemonic, "ALIGN")) {
            return try self.parseAlignDirective(line, line_num, allocator);
        }
        
        // Check for ORG directive
        if (std.mem.eql(u8, mnemonic, "ORG")) {
            return try self.parseOrgDirective(line, line_num, allocator);
        }
        
        // Check for BINFILE directive
        if (std.mem.eql(u8, mnemonic, "BINFILE")) {
            return try self.parseBinFileDirective(line, line_num, allocator);
        }
        
        // Check for LIST/NOLIST directives
        if (std.mem.eql(u8, mnemonic, "LIST") or std.mem.eql(u8, mnemonic, "NOLIST")) {
            return try self.parseListDirective(mnemonic, line_num);
        }
        
        // Get the rest of the line (operands)
        const rest_start = mnemonic.ptr + mnemonic.len - line.ptr;
        var operands_str = if (rest_start < line.len) 
            std.mem.trim(u8, line[rest_start..], &std.ascii.whitespace)
        else 
            "";
        
        // Strip comments (// at end of line)
        if (std.mem.indexOf(u8, operands_str, "//")) |comment_idx| {
            operands_str = std.mem.trim(u8, operands_str[0..comment_idx], &std.ascii.whitespace);
        }
        
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
    
    /// Parse data directive (DU8, DU16, DU32, DU64)
    fn parseDataDirective(self: *X64Assembler, line: []const u8, mnemonic: []const u8, line_num: usize, allocator: std.mem.Allocator) AssemblerError!Instruction {
        
        // Determine size
        const size: OperandSize = if (std.mem.eql(u8, mnemonic, "DU8"))
            .byte
        else if (std.mem.eql(u8, mnemonic, "DU16"))
            .word
        else if (std.mem.eql(u8, mnemonic, "DU32"))
            .dword
        else
            .qword;
        
        // Get the data part (everything after mnemonic)
        const rest_start = mnemonic.ptr + mnemonic.len - line.ptr;
        var data_str = if (rest_start < line.len) 
            std.mem.trim(u8, line[rest_start..], &std.ascii.whitespace)
        else 
            "";
        
        // Strip trailing semicolon if present
        if (std.mem.endsWith(u8, data_str, ";")) {
            data_str = std.mem.trim(u8, data_str[0..data_str.len-1], &std.ascii.whitespace);
        }
        
        // Strip comments
        if (std.mem.indexOf(u8, data_str, "//")) |comment_idx| {
            data_str = std.mem.trim(u8, data_str[0..comment_idx], &std.ascii.whitespace);
        }
        
        // Parse data values
        var data_bytes = std.ArrayList(u8).empty;
        errdefer data_bytes.deinit(allocator);
        
        // Check for string literal
        if (std.mem.startsWith(u8, data_str, "\"")) {
            // Parse string literal
            const end_quote = std.mem.lastIndexOfScalar(u8, data_str, '"') orelse return error.SyntaxError;
            if (end_quote == 0) return error.SyntaxError;
            
            const string_content = data_str[1..end_quote];
            
            // Process escape sequences
            var i: usize = 0;
            while (i < string_content.len) : (i += 1) {
                if (string_content[i] == '\\' and i + 1 < string_content.len) {
                    // Handle escape sequences
                    i += 1;
                    const escaped = switch (string_content[i]) {
                        'n' => '\n',
                        't' => '\t',
                        'r' => '\r',
                        '\\' => '\\',
                        '"' => '"',
                        '0' => 0,
                        else => string_content[i],
                    };
                    try data_bytes.append(allocator, escaped);
                } else {
                    try data_bytes.append(allocator, string_content[i]);
                }
            }
            
            // Check for additional comma-separated values after string
            const after_string = std.mem.trim(u8, data_str[end_quote+1..], &std.ascii.whitespace);
            if (std.mem.startsWith(u8, after_string, ",")) {
                const remaining = std.mem.trim(u8, after_string[1..], &std.ascii.whitespace);
                try self.parseDataValues(remaining, size, &data_bytes, allocator);
            }
        } else {
            // Parse comma-separated numeric values
            try self.parseDataValues(data_str, size, &data_bytes, allocator);
        }
        
        return Instruction{
            .mnemonic = mnemonic,
            .operands = &[_]OperandType{},
            .location = .{
                .line = line_num,
                .column = 0,
            },
            .directive = .{
                .data = .{
                    .size = size,
                    .values = try data_bytes.toOwnedSlice(allocator),
                },
            },
        };
    }
    
    /// Parse numeric data values
    fn parseDataValues(_: *X64Assembler, values_str: []const u8, size: OperandSize, data_bytes: *std.ArrayList(u8), allocator: std.mem.Allocator) AssemblerError!void {
        
        var parts = std.mem.splitScalar(u8, values_str, ',');
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, &std.ascii.whitespace);
            if (trimmed.len == 0) continue;
            
            // Check for DUP syntax: "count DUP (value)"
            if (std.mem.indexOf(u8, trimmed, " DUP ")) |dup_idx| {
                const count_str = std.mem.trim(u8, trimmed[0..dup_idx], &std.ascii.whitespace);
                const rest = std.mem.trim(u8, trimmed[dup_idx + 5..], &std.ascii.whitespace);
                
                // Parse count
                const count = if (std.mem.startsWith(u8, count_str, "0x"))
                    std.fmt.parseInt(usize, count_str[2..], 16) catch return error.InvalidImmediate
                else
                    std.fmt.parseInt(usize, count_str, 10) catch return error.InvalidImmediate;
                
                // Parse value in parentheses
                if (!std.mem.startsWith(u8, rest, "(") or !std.mem.endsWith(u8, rest, ")")) {
                    return error.SyntaxError;
                }
                
                const value_str = std.mem.trim(u8, rest[1..rest.len-1], &std.ascii.whitespace);
                const value = if (std.mem.startsWith(u8, value_str, "0x"))
                    std.fmt.parseInt(i64, value_str[2..], 16) catch return error.InvalidImmediate
                else
                    std.fmt.parseInt(i64, value_str, 10) catch return error.InvalidImmediate;
                
                // Repeat value 'count' times
                var i: usize = 0;
                while (i < count) : (i += 1) {
                    switch (size) {
                        .byte => {
                            const val: u8 = @intCast(@as(u64, @bitCast(value)) & 0xFF);
                            try data_bytes.append(allocator, val);
                        },
                        .word => {
                            const val: u16 = @intCast(@as(u64, @bitCast(value)) & 0xFFFF);
                            const bytes = std.mem.toBytes(val);
                            try data_bytes.appendSlice(allocator, &bytes);
                        },
                        .dword => {
                            const val: u32 = @intCast(@as(u64, @bitCast(value)) & 0xFFFFFFFF);
                            const bytes = std.mem.toBytes(val);
                            try data_bytes.appendSlice(allocator, &bytes);
                        },
                        .qword => {
                            const bytes = std.mem.toBytes(value);
                            try data_bytes.appendSlice(allocator, &bytes);
                        },
                    }
                }
                continue;
            }
            
            // Try to parse as number
            var value: i64 = 0;
            if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
                value = std.fmt.parseInt(i64, trimmed[2..], 16) catch return error.InvalidImmediate;
            } else {
                value = std.fmt.parseInt(i64, trimmed, 10) catch return error.InvalidImmediate;
            }
            
            // Encode based on size
            switch (size) {
                .byte => {
                    const val: u8 = @intCast(@as(u64, @bitCast(value)) & 0xFF);
                    try data_bytes.append(allocator, val);
                },
                .word => {
                    const val: u16 = @intCast(@as(u64, @bitCast(value)) & 0xFFFF);
                    const bytes = std.mem.toBytes(val);
                    try data_bytes.appendSlice(allocator, &bytes);
                },
                .dword => {
                    const val: u32 = @intCast(@as(u64, @bitCast(value)) & 0xFFFFFFFF);
                    const bytes = std.mem.toBytes(val);
                    try data_bytes.appendSlice(allocator, &bytes);
                },
                .qword => {
                    const bytes = std.mem.toBytes(value);
                    try data_bytes.appendSlice(allocator, &bytes);
                },
            }
        }
    }
    
    /// Parse IMPORT directive
    fn parseImportDirective(self: *X64Assembler, line: []const u8, line_num: usize, allocator: std.mem.Allocator) AssemblerError!Instruction {
        _ = self;
        
        // Get symbols after IMPORT keyword
        const import_start = "IMPORT".len;
        var symbols_str = if (import_start < line.len) 
            std.mem.trim(u8, line[import_start..], &std.ascii.whitespace)
        else 
            "";
        
        // Strip trailing semicolon
        if (std.mem.endsWith(u8, symbols_str, ";")) {
            symbols_str = symbols_str[0..symbols_str.len-1];
        }
        
        // Parse comma-separated symbols
        var symbols = std.ArrayList([]const u8).empty;
        errdefer symbols.deinit(allocator);
        
        var parts = std.mem.splitScalar(u8, symbols_str, ',');
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, &std.ascii.whitespace);
            if (trimmed.len > 0) {
                try symbols.append(allocator, trimmed);
            }
        }
        
        return Instruction{
            .mnemonic = "IMPORT",
            .operands = &[_]OperandType{},
            .location = .{
                .line = line_num,
                .column = 0,
            },
            .directive = .{
                .import_symbols = try symbols.toOwnedSlice(allocator),
            },
        };
    }
    
    /// Parse USE directive
    fn parseUseDirective(self: *X64Assembler, mnemonic: []const u8, line_num: usize) AssemblerError!Instruction {
        _ = self;
        
        const mode = if (std.mem.eql(u8, mnemonic, "USE16"))
            assembler.Directive{ .use_mode = .use16 }
        else if (std.mem.eql(u8, mnemonic, "USE32"))
            assembler.Directive{ .use_mode = .use32 }
        else
            assembler.Directive{ .use_mode = .use64 };
        
        return Instruction{
            .mnemonic = mnemonic,
            .operands = &[_]OperandType{},
            .location = .{
                .line = line_num,
                .column = 0,
            },
            .directive = mode,
        };
    }
    
    /// Parse ALIGN directive
    fn parseAlignDirective(self: *X64Assembler, line: []const u8, line_num: usize, allocator: std.mem.Allocator) AssemblerError!Instruction {
        _ = allocator;
        _ = self;
        
        const align_start = "ALIGN".len;
        const params_str = if (align_start < line.len)
            std.mem.trim(u8, line[align_start..], &std.ascii.whitespace)
        else
            return error.SyntaxError;
        
        // Parse "boundary, fill_byte"
        var parts = std.mem.splitScalar(u8, params_str, ',');
        const boundary_str = std.mem.trim(u8, parts.next() orelse return error.SyntaxError, &std.ascii.whitespace);
        const fill_str = std.mem.trim(u8, parts.next() orelse "0", &std.ascii.whitespace);
        
        const boundary = std.fmt.parseInt(usize, boundary_str, 10) catch return error.InvalidImmediate;
        const fill_byte = std.fmt.parseInt(u8, fill_str, 10) catch return error.InvalidImmediate;
        
        return Instruction{
            .mnemonic = "ALIGN",
            .operands = &[_]OperandType{},
            .location = .{
                .line = line_num,
                .column = 0,
            },
            .directive = .{
                .align_directive = .{
                    .boundary = boundary,
                    .fill_byte = fill_byte,
                },
            },
        };
    }
    
    /// Parse ORG directive
    fn parseOrgDirective(self: *X64Assembler, line: []const u8, line_num: usize, allocator: std.mem.Allocator) AssemblerError!Instruction {
        _ = allocator;
        _ = self;
        
        const org_start = "ORG".len;
        const addr_str = if (org_start < line.len)
            std.mem.trim(u8, line[org_start..], &std.ascii.whitespace)
        else
            return error.SyntaxError;
        
        const addr = if (std.mem.startsWith(u8, addr_str, "0x"))
            std.fmt.parseInt(usize, addr_str[2..], 16) catch return error.InvalidImmediate
        else
            std.fmt.parseInt(usize, addr_str, 10) catch return error.InvalidImmediate;
        
        return Instruction{
            .mnemonic = "ORG",
            .operands = &[_]OperandType{},
            .location = .{
                .line = line_num,
                .column = 0,
            },
            .directive = .{
                .org = addr,
            },
        };
    }
    
    /// Parse BINFILE directive - includes binary file contents
    fn parseBinFileDirective(self: *X64Assembler, line: []const u8, line_num: usize, allocator: std.mem.Allocator) AssemblerError!Instruction {
        _ = self;
        
        const binfile_start = "BINFILE".len;
        var filename_str = if (binfile_start < line.len)
            std.mem.trim(u8, line[binfile_start..], &std.ascii.whitespace)
        else
            return error.SyntaxError;
        
        // Strip trailing semicolon
        if (std.mem.endsWith(u8, filename_str, ";")) {
            filename_str = filename_str[0..filename_str.len-1];
            filename_str = std.mem.trim(u8, filename_str, &std.ascii.whitespace);
        }
        
        // Strip quotes
        if (std.mem.startsWith(u8, filename_str, "\"") and std.mem.endsWith(u8, filename_str, "\"")) {
            filename_str = filename_str[1..filename_str.len-1];
        } else if (std.mem.startsWith(u8, filename_str, "'") and std.mem.endsWith(u8, filename_str, "'")) {
            filename_str = filename_str[1..filename_str.len-1];
        } else {
            return error.SyntaxError;
        }
        
        // Read the binary file contents during parsing
        // This is simpler than trying to read during encoding
        const cwd = std.Io.Dir.cwd();
        var io_init = std.Io.Threaded.init(allocator, .{});
        const io = io_init.io();
        
        const file_contents = cwd.readFileAlloc(io, filename_str, allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch |err| {
            std.debug.print("Error reading file '{s}': {}\n", .{filename_str, err});
            return error.FileNotFound;
        };
        // Don't defer free - the data directive owns this memory now
        
        // Convert to data directive
        return Instruction{
            .mnemonic = "BINFILE",
            .operands = &[_]OperandType{},
            .location = .{
                .line = line_num,
                .column = 0,
            },
            .directive = .{
                .data = .{
                    .size = .byte,
                    .values = file_contents,
                },
            },
        };
    }
    
    /// Parse LIST/NOLIST directive
    fn parseListDirective(self: *X64Assembler, mnemonic: []const u8, line_num: usize) AssemblerError!Instruction {
        _ = self;
        
        const control = if (std.mem.eql(u8, mnemonic, "LIST"))
            assembler.Directive{ .list_control = .list }
        else
            assembler.Directive{ .list_control = .nolist };
        
        return Instruction{
            .mnemonic = mnemonic,
            .operands = &[_]OperandType{},
            .location = .{
                .line = line_num,
                .column = 0,
            },
            .directive = control,
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
            
            // Try to parse as memory operand (includes type-prefixed forms)
            if (std.mem.startsWith(u8, trimmed, "[") and std.mem.endsWith(u8, trimmed, "]")) {
                if (try self.parseMemoryOperand(trimmed)) |mem| {
                    try operands.append(allocator, mem);
                    continue;
                }
            }
            
            // Try to parse as type-prefixed memory operand (e.g., "U64 SF_ARG1[RBP]")
            if (try self.parseTypePrefixedOperand(trimmed, allocator)) |op| {
                try operands.append(allocator, op);
                continue;
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
    
    /// Parse type-prefixed memory operand (e.g., "U64 SF_ARG1[RBP]" or "I8 0x10[RSI]")
    /// This is a TempleOS-specific feature where you can prefix memory operands with type hints
    /// and use HolyC constant expressions
    fn parseTypePrefixedOperand(self: *X64Assembler, text: []const u8, allocator: std.mem.Allocator) !?OperandType {
        _ = allocator;
        
        // Check for type prefix (U64, I64, U32, I32, U16, I16, U8, I8)
        const type_prefixes = [_][]const u8{ "U64", "I64", "U32", "I32", "U16", "I16", "U8", "I8" };
        
        for (type_prefixes) |prefix| {
            if (std.mem.startsWith(u8, text, prefix)) {
                // Check if followed by whitespace
                if (text.len > prefix.len and std.ascii.isWhitespace(text[prefix.len])) {
                    const rest = std.mem.trim(u8, text[prefix.len..], &std.ascii.whitespace);
                    
                    // Determine size from type
                    const size: OperandSize = if (std.mem.eql(u8, prefix, "U8") or std.mem.eql(u8, prefix, "I8"))
                        .byte
                    else if (std.mem.eql(u8, prefix, "U16") or std.mem.eql(u8, prefix, "I16"))
                        .word
                    else if (std.mem.eql(u8, prefix, "U32") or std.mem.eql(u8, prefix, "I32"))
                        .dword
                    else
                        .qword;
                    
                    // Check if it's a memory operand with brackets
                    if (std.mem.indexOf(u8, rest, "[")) |bracket_idx| {
                        // Split into expression and register parts
                        // e.g., "SF_ARG1[RBP]" -> expr="SF_ARG1", reg="[RBP]"
                        // or   "sizeof(MyStruct)+8[RBP]" -> expr="sizeof(MyStruct)+8", reg="[RBP]"
                        const expr_str = std.mem.trim(u8, rest[0..bracket_idx], &std.ascii.whitespace);
                        const bracket_part = rest[bracket_idx..];
                        
                        // Try to evaluate the expression using the expression evaluator
                        var displacement: i32 = 0;
                        if (try expr_eval.evalConstExpr(&self.expr_ctx, expr_str)) |value| {
                            displacement = @intCast(value);
                        } else {
                            // Expression cannot be evaluated - might need symbol table
                            // For now, treat as zero displacement
                            // TODO: Report warning or error
                            displacement = 0;
                        }
                        
                        // Parse the register part
                        if (std.mem.startsWith(u8, bracket_part, "[") and std.mem.endsWith(u8, bracket_part, "]")) {
                            const reg_str = std.mem.trim(u8, bracket_part[1..bracket_part.len-1], &std.ascii.whitespace);
                            
                            if (Register.fromString(reg_str)) |reg| {
                                return .{
                                    .memory = .{
                                        .base = reg.getHardwareId(),
                                        .index = null,
                                        .scale = 1,
                                        .displacement = displacement,
                                        .size = size,
                                        .segment = null,
                                    },
                                };
                            }
                        }
                    }
                }
            }
        }
        
        return null;
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
    
    /// Encode instructions to machine code with multi-pass label resolution
    pub fn encode(self: *X64Assembler, instructions: []Instruction, allocator: std.mem.Allocator) AssemblerError![]u8 {
        // Pass 1: Encode all instructions and build instruction-index-to-byte-offset map
        var code: std.ArrayList(u8) = .empty;
        errdefer code.deinit(allocator);
        
        // Track fixup locations for label references
        var fixups = std.ArrayList(Fixup).empty;
        defer fixups.deinit(allocator);
        
        // Map from instruction index to byte offset
        var instr_offsets = std.ArrayList(usize).empty;
        defer instr_offsets.deinit(allocator);
        
        for (instructions) |instr| {
            // Record where this instruction starts
            try instr_offsets.append(allocator, code.items.len);
            try self.encodeInstructionWithFixups(instr, &code, &fixups, allocator);
        }
        
        // Pass 2: Convert label instruction indices to byte offsets
        var label_iter = self.labels.iterator();
        while (label_iter.next()) |entry| {
            var label = entry.value_ptr.*;
            const instr_idx = label.offset;
            
            // Convert instruction index to byte offset
            if (instr_idx < instr_offsets.items.len) {
                label.offset = instr_offsets.items[instr_idx];
            } else {
                // Label points past the end - use final offset
                label.offset = code.items.len;
            }
            entry.value_ptr.* = label;
        }
        
        // Pass 3: Resolve label references and apply fixups
        for (fixups.items) |fixup| {
            if (self.labels.get(fixup.label_name)) |label| {
                const target_offset = label.offset;
                const fixup_offset = fixup.location;
                
                // Calculate relative offset from end of instruction
                // For CALL/JMP, the offset is from the byte after the instruction
                const rel_offset: i32 = @intCast(@as(i64, @intCast(target_offset)) - 
                                                   @as(i64, @intCast(fixup_offset + fixup.size)));
                
                // Patch the code with the calculated offset
                switch (fixup.size) {
                    1 => {
                        const rel8: i8 = @intCast(rel_offset);
                        code.items[fixup_offset] = @bitCast(rel8);
                    },
                    4 => {
                        const bytes = std.mem.toBytes(rel_offset);
                        @memcpy(code.items[fixup_offset..][0..4], &bytes);
                    },
                    else => return error.InvalidOperand,
                }
            } else {
                // Label not found - this is an error
                return error.UnresolvedLabel;
            }
        }
        
        return code.toOwnedSlice(allocator);
    }
    
    /// Fixup record for label references
    const Fixup = struct {
        location: usize,      // Offset in code where fixup is needed
        size: u8,             // Size of fixup (1 for rel8, 4 for rel32)
        label_name: []const u8, // Name of label to resolve
    };
    
    /// Encode a single instruction and record any label fixups needed
    fn encodeInstructionWithFixups(self: *X64Assembler, instr: Instruction, code: *std.ArrayList(u8), fixups: *std.ArrayList(Fixup), allocator: std.mem.Allocator) !void {
        // Handle directives first
        if (instr.directive) |directive| {
            switch (directive) {
                .data => |data| {
                    // Emit data bytes directly
                    try code.appendSlice(allocator, data.values);
                    return;
                },
                .use_mode => {
                    // USE directives don't emit code, they just change assembler state
                    // TODO: Track current mode for proper encoding
                    return;
                },
                .import_symbols => {
                    // IMPORT directives don't emit code, they're metadata
                    return;
                },
                .align_directive => |align_data| {
                    // Align to boundary
                    const current_offset = code.items.len;
                    const aligned_offset = (current_offset + align_data.boundary - 1) / align_data.boundary * align_data.boundary;
                    const padding = aligned_offset - current_offset;
                    
                    // Fill with padding bytes
                    var i: usize = 0;
                    while (i < padding) : (i += 1) {
                        try code.append(allocator, align_data.fill_byte);
                    }
                    return;
                },
                .org => {
                    // ORG directive sets the code position
                    // For now, we'll treat it as metadata
                    // TODO: Implement proper ORG support with code positioning
                    return;
                },
                .binfile => {
                    // BINFILE is converted to data directive during parsing
                    // This case should not be reached
                    unreachable;
                },
                .list_control => {
                    // LIST/NOLIST controls listing output
                    return;
                },
            }
        }
        
        const mnemonic = instr.mnemonic;
        
        // Handle CALL with labels - record fixup
        if (std.mem.eql(u8, mnemonic, "CALL")) {
            if (instr.operands.len == 1 and instr.operands[0] == .label) {
                const label_name = instr.operands[0].label.name;
                try code.append(allocator, 0xE8); // CALL rel32
                const fixup_loc = code.items.len;
                try code.append(allocator, 0x00);
                try code.append(allocator, 0x00);
                try code.append(allocator, 0x00);
                try code.append(allocator, 0x00);
                try fixups.append(allocator, .{
                    .location = fixup_loc,
                    .size = 4,
                    .label_name = label_name,
                });
                return;
            }
        }
        
        // Handle JMP with labels - record fixup
        if (std.mem.eql(u8, mnemonic, "JMP")) {
            if (instr.operands.len == 1 and instr.operands[0] == .label) {
                const label_name = instr.operands[0].label.name;
                try code.append(allocator, 0xE9); // JMP rel32
                const fixup_loc = code.items.len;
                try code.append(allocator, 0x00);
                try code.append(allocator, 0x00);
                try code.append(allocator, 0x00);
                try code.append(allocator, 0x00);
                try fixups.append(allocator, .{
                    .location = fixup_loc,
                    .size = 4,
                    .label_name = label_name,
                });
                return;
            }
        }
        
        // Handle conditional jumps with labels - record fixup
        const jump_mnemonics = [_][]const u8{ "JO", "JNO", "JB", "JAE", "JE", "JNE", "JBE", "JA", 
                                              "JS", "JNS", "JP", "JNP", "JL", "JGE", "JLE", "JG",
                                              "JZ", "JNZ", "JC", "JNC" };
        for (jump_mnemonics) |jmp| {
            if (std.mem.eql(u8, mnemonic, jmp)) {
                if (instr.operands.len == 1 and instr.operands[0] == .label) {
                    const label_name = instr.operands[0].label.name;
                    // For now, use short form (rel8)
                    const jump_map = std.StaticStringMap(u8).initComptime(.{
                        .{ "JO",   0x70 }, .{ "JNO",  0x71 },
                        .{ "JB",   0x72 }, .{ "JAE",  0x73 },
                        .{ "JE",   0x74 }, .{ "JNE",  0x75 },
                        .{ "JBE",  0x76 }, .{ "JA",   0x77 },
                        .{ "JS",   0x78 }, .{ "JNS",  0x79 },
                        .{ "JP",   0x7A }, .{ "JNP",  0x7B },
                        .{ "JL",   0x7C }, .{ "JGE",  0x7D },
                        .{ "JLE",  0x7E }, .{ "JG",   0x7F },
                        .{ "JZ",   0x74 }, .{ "JNZ",  0x75 },
                        .{ "JC",   0x72 }, .{ "JNC",  0x73 },
                    });
                    const opcode = jump_map.get(mnemonic).?;
                    try code.append(allocator, opcode);
                    const fixup_loc = code.items.len;
                    try code.append(allocator, 0x00);
                    try fixups.append(allocator, .{
                        .location = fixup_loc,
                        .size = 1,
                        .label_name = label_name,
                    });
                    return;
                }
            }
        }
        
        // For all other instructions, use the existing encodeInstruction
        try self.encodeInstruction(instr, code, allocator);
    }
    
    /// Helper: Encode ModR/M byte and optional SIB/displacement for memory operands
    fn encodeModRM(_: *X64Assembler, reg: u8, mem: assembler.MemoryOperand, code: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        
        const base = mem.base orelse return error.InvalidMemoryOperand;
        const base_masked = base & 0x7;
        const reg_masked = reg & 0x7;
        
        // Determine mod field based on displacement
        const disp = mem.displacement;
        const mod: u8 = if (disp == 0 and base_masked != 5) // RBP requires displacement
            0b00 // No displacement
        else if (disp >= -128 and disp <= 127)
            0b01 // 8-bit displacement
        else
            0b10; // 32-bit displacement
        
        // Check if we need SIB byte (RSP/R12 always need SIB)
        const needs_sib = (base_masked == 4);
        
        if (needs_sib) {
            // ModR/M byte with SIB indicator
            const modrm = (mod << 6) | (reg_masked << 3) | 0b100;
            try code.append(allocator, modrm);
            
            // SIB byte: scale=0, index=none (0b100), base=actual base
            const sib = (0b00 << 6) | (0b100 << 3) | base_masked;
            try code.append(allocator, sib);
        } else {
            // Direct ModR/M encoding
            const modrm = (mod << 6) | (reg_masked << 3) | base_masked;
            try code.append(allocator, modrm);
        }
        
        // Emit displacement if needed
        if (mod == 0b01) {
            // 8-bit displacement
            try code.append(allocator, @bitCast(@as(i8, @intCast(disp))));
        } else if (mod == 0b10 or (mod == 0b00 and base_masked == 5)) {
            // 32-bit displacement (or RBP with 0 displacement needs disp32)
            const disp32: i32 = @intCast(disp);
            const bytes = std.mem.toBytes(disp32);
            try code.appendSlice(allocator, &bytes);
        }
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
        // Handle IMUL2 two-operand form: IMUL2 r64, r/m64 (TempleOS syntax)
        if (std.mem.eql(u8, mnemonic, "IMUL2") and instr.operands.len == 2) {
            const dest = instr.operands[0];
            const src = instr.operands[1];
            
            if (dest == .register and src == .register) {
                const dst_reg = dest.register;
                const src_reg = src.register;
                
                if (dst_reg.size == .qword and src_reg.size == .qword) {
                    // IMUL2 r64, r64: REX.W + 0x0F 0xAF /r
                    var rex: u8 = 0x48;
                    if (dst_reg.id >= 8) rex |= 0x04; // REX.R
                    if (src_reg.id >= 8) rex |= 0x01; // REX.B
                    try code.append(allocator, rex);
                    try code.append(allocator, 0x0F);
                    try code.append(allocator, 0xAF);
                    const modrm = 0xC0 | ((dst_reg.id & 0x7) << 3) | (src_reg.id & 0x7);
                    try code.append(allocator, modrm);
                    return true;
                }
            }
            
            // TODO: Support IMUL2 r64, [mem] and IMUL2 r64, imm forms
            return false;
        }
        
        // Handle one-operand forms: MUL/IMUL/DIV/IDIV r64
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
        
        // MOV instruction with full operand support
        else if (std.mem.eql(u8, mnemonic, "MOV")) {
            if (instr.operands.len == 2) {
                const dest = instr.operands[0];
                const src = instr.operands[1];
                
                switch (dest) {
                    .register => |dst_reg| {
                        switch (src) {
                            // MOV reg, reg
                            .register => |src_reg| {
                                // Ensure same size
                                if (dst_reg.size != src_reg.size) {
                                    return error.OperandSizeMismatch;
                                }
                                
                                if (dst_reg.size == .qword) {
                                    // REX.W prefix
                                    var rex: u8 = 0x48;
                                    if (dst_reg.id >= 8) rex |= 0x01; // REX.B
                                    if (src_reg.id >= 8) rex |= 0x04; // REX.R
                                    try code.append(allocator, rex);
                                    
                                    // MOV r64, r64: 0x89 ModR/M
                                    try code.append(allocator, 0x89);
                                    const modrm = 0xC0 | ((src_reg.id & 0x7) << 3) | (dst_reg.id & 0x7);
                                    try code.append(allocator, modrm);
                                } else {
                                    // For now, only support qword
                                    return error.UnsupportedOperandSize;
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
                                } else {
                                    return error.UnsupportedOperandSize;
                                }
                            },
                            
                            // MOV reg, [mem]
                            .memory => |mem| {
                                if (dst_reg.size == .qword) {
                                    // MOV r64, [mem]: REX.W + 0x8B + ModR/M + disp
                                    var rex: u8 = 0x48;
                                    if (dst_reg.id >= 8) rex |= 0x04; // REX.R
                                    if (mem.base) |base| {
                                        if (base >= 8) rex |= 0x01; // REX.B
                                    }
                                    try code.append(allocator, rex);
                                    try code.append(allocator, 0x8B); // MOV r64, r/m64
                                    
                                    // Encode ModR/M and SIB if needed
                                    try self.encodeModRM(dst_reg.id, mem, code, allocator);
                                } else {
                                    return error.UnsupportedOperandSize;
                                }
                            },
                            
                            else => return error.InvalidOperand,
                        }
                    },
                    .memory => |mem| {
                        switch (src) {
                            // MOV [mem], reg
                            .register => |src_reg| {
                                if (src_reg.size == .qword) {
                                    // MOV [mem], r64: REX.W + 0x89 + ModR/M + disp
                                    var rex: u8 = 0x48;
                                    if (src_reg.id >= 8) rex |= 0x04; // REX.R
                                    if (mem.base) |base| {
                                        if (base >= 8) rex |= 0x01; // REX.B
                                    }
                                    try code.append(allocator, rex);
                                    try code.append(allocator, 0x89); // MOV r/m64, r64
                                    
                                    // Encode ModR/M and SIB if needed
                                    try self.encodeModRM(src_reg.id, mem, code, allocator);
                                } else {
                                    return error.UnsupportedOperandSize;
                                }
                            },
                            
                            // MOV [mem], imm
                            .immediate => |imm| {
                                // MOV [mem], imm32: REX.W + 0xC7 /0 + ModR/M + disp + imm32
                                var rex: u8 = 0x48;
                                if (mem.base) |base| {
                                    if (base >= 8) rex |= 0x01; // REX.B
                                }
                                try code.append(allocator, rex);
                                try code.append(allocator, 0xC7); // MOV r/m64, imm32
                                
                                // Encode ModR/M with reg field = 0 (/0)
                                try self.encodeModRM(0, mem, code, allocator);
                                
                                // Emit immediate (sign-extended from 32-bit)
                                const val: i32 = @intCast(imm.value);
                                const bytes = std.mem.toBytes(val);
                                try code.appendSlice(allocator, &bytes);
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
        
        // x87 FPU Instructions
        else if (std.mem.eql(u8, mnemonic, "FLD")) {
            // FLD - Load floating point value to ST0
            if (instr.operands.len == 1) {
                const src = instr.operands[0];
                if (src == .memory) {
                    const mem = src.memory;
                    // FLD qword [mem] - 0xDD /0
                    try code.append(allocator, 0xDD);
                    try self.encodeModRM(0, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FST")) {
            // FST - Store ST0 to memory (without pop)
            if (instr.operands.len == 1) {
                const dst = instr.operands[0];
                if (dst == .memory) {
                    const mem = dst.memory;
                    // FST qword [mem] - 0xDD /2
                    try code.append(allocator, 0xDD);
                    try self.encodeModRM(2, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FSTP")) {
            // FSTP - Store ST0 to memory and pop
            if (instr.operands.len == 1) {
                const dst = instr.operands[0];
                if (dst == .memory) {
                    const mem = dst.memory;
                    // FSTP qword [mem] - 0xDD /3
                    try code.append(allocator, 0xDD);
                    try self.encodeModRM(3, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FADD")) {
            // FADD - Add memory to ST0
            if (instr.operands.len == 1) {
                const src = instr.operands[0];
                if (src == .memory) {
                    const mem = src.memory;
                    // FADD qword [mem] - 0xDC /0
                    try code.append(allocator, 0xDC);
                    try self.encodeModRM(0, mem, code, allocator);
                }
            } else if (instr.operands.len == 2) {
                // FADDP ST(i), ST0 - pop and add
                // For now, just handle FADDP with implicit operands
                try code.append(allocator, 0xDE);
                try code.append(allocator, 0xC1); // FADDP ST(1), ST0
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FADDP")) {
            // FADDP - Add ST0 to ST(1) and pop
            try code.append(allocator, 0xDE);
            try code.append(allocator, 0xC1); // FADDP ST(1), ST0
        }
        else if (std.mem.eql(u8, mnemonic, "FSUB")) {
            // FSUB - Subtract memory from ST0
            if (instr.operands.len == 1) {
                const src = instr.operands[0];
                if (src == .memory) {
                    const mem = src.memory;
                    // FSUB qword [mem] - 0xDC /4
                    try code.append(allocator, 0xDC);
                    try self.encodeModRM(4, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FSUBP")) {
            // FSUBP - Subtract ST0 from ST(1) and pop
            try code.append(allocator, 0xDE);
            try code.append(allocator, 0xE9); // FSUBP ST(1), ST0
        }
        else if (std.mem.eql(u8, mnemonic, "FMUL")) {
            // FMUL - Multiply ST0 by memory
            if (instr.operands.len == 1) {
                const src = instr.operands[0];
                if (src == .memory) {
                    const mem = src.memory;
                    // FMUL qword [mem] - 0xDC /1
                    try code.append(allocator, 0xDC);
                    try self.encodeModRM(1, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FMULP")) {
            // FMULP - Multiply ST(1) by ST0 and pop
            try code.append(allocator, 0xDE);
            try code.append(allocator, 0xC9); // FMULP ST(1), ST0
        }
        else if (std.mem.eql(u8, mnemonic, "FDIV")) {
            // FDIV - Divide ST0 by memory
            if (instr.operands.len == 1) {
                const src = instr.operands[0];
                if (src == .memory) {
                    const mem = src.memory;
                    // FDIV qword [mem] - 0xDC /6
                    try code.append(allocator, 0xDC);
                    try self.encodeModRM(6, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FDIVP")) {
            // FDIVP - Divide ST(1) by ST0 and pop
            try code.append(allocator, 0xDE);
            try code.append(allocator, 0xF9); // FDIVP ST(1), ST0
        }
        else if (std.mem.eql(u8, mnemonic, "FCHS")) {
            // FCHS - Change sign of ST0
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xE0);
        }
        else if (std.mem.eql(u8, mnemonic, "FABS")) {
            // FABS - Absolute value of ST0
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xE1);
        }
        else if (std.mem.eql(u8, mnemonic, "FSQRT")) {
            // FSQRT - Square root of ST0
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xFA);
        }
        
        // x87 Transcendental Functions
        else if (std.mem.eql(u8, mnemonic, "FSIN")) {
            // FSIN - Sine of ST0
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xFE);
        }
        else if (std.mem.eql(u8, mnemonic, "FCOS")) {
            // FCOS - Cosine of ST0
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xFF);
        }
        else if (std.mem.eql(u8, mnemonic, "FSINCOS")) {
            // FSINCOS - Sine and cosine of ST0 (replaces ST0 with sin, pushes cos)
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xFB);
        }
        else if (std.mem.eql(u8, mnemonic, "FPTAN")) {
            // FPTAN - Partial tangent of ST0
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF2);
        }
        else if (std.mem.eql(u8, mnemonic, "FPATAN")) {
            // FPATAN - Partial arctangent ST1/ST0, pop
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF3);
        }
        else if (std.mem.eql(u8, mnemonic, "F2XM1")) {
            // F2XM1 - 2^ST0 - 1
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF0);
        }
        else if (std.mem.eql(u8, mnemonic, "FYL2X")) {
            // FYL2X - ST1 * log2(ST0), pop
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF1);
        }
        else if (std.mem.eql(u8, mnemonic, "FYL2XP1")) {
            // FYL2XP1 - ST1 * log2(ST0+1), pop
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF9);
        }
        else if (std.mem.eql(u8, mnemonic, "FSCALE")) {
            // FSCALE - Scale ST0 by ST1 (ST0 = ST0 * 2^ST1)
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xFD);
        }
        else if (std.mem.eql(u8, mnemonic, "FRNDINT")) {
            // FRNDINT - Round ST0 to integer
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xFC);
        }
        else if (std.mem.eql(u8, mnemonic, "FXTRACT")) {
            // FXTRACT - Extract exponent and significand
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF4);
        }
        
        // x87 Comparison Instructions
        else if (std.mem.eql(u8, mnemonic, "FCOM")) {
            // FCOM - Compare ST0 with memory or ST(i)
            if (instr.operands.len == 0) {
                // FCOM ST(1)
                try code.append(allocator, 0xD8);
                try code.append(allocator, 0xD1);
            } else if (instr.operands.len == 1) {
                const src = instr.operands[0];
                if (src == .memory) {
                    const mem = src.memory;
                    // FCOM qword [mem] - 0xDC /2
                    try code.append(allocator, 0xDC);
                    try self.encodeModRM(2, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FCOMP")) {
            // FCOMP - Compare ST0 with memory or ST(i) and pop
            if (instr.operands.len == 0) {
                // FCOMP ST(1)
                try code.append(allocator, 0xD8);
                try code.append(allocator, 0xD9);
            } else if (instr.operands.len == 1) {
                const src = instr.operands[0];
                if (src == .memory) {
                    const mem = src.memory;
                    // FCOMP qword [mem] - 0xDC /3
                    try code.append(allocator, 0xDC);
                    try self.encodeModRM(3, mem, code, allocator);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FCOMPP")) {
            // FCOMPP - Compare ST0 with ST1 and pop twice
            try code.append(allocator, 0xDE);
            try code.append(allocator, 0xD9);
        }
        else if (std.mem.eql(u8, mnemonic, "FCOMI")) {
            // FCOMI - Compare ST0 with ST(i) and set EFLAGS
            if (instr.operands.len == 1 and instr.operands[0] == .register) {
                // For simplicity, assume ST(1)
                try code.append(allocator, 0xDB);
                try code.append(allocator, 0xF1);
            } else {
                // Default to ST(1)
                try code.append(allocator, 0xDB);
                try code.append(allocator, 0xF1);
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FCOMIP")) {
            // FCOMIP - Compare ST0 with ST(i), set EFLAGS, and pop
            if (instr.operands.len == 1 and instr.operands[0] == .register) {
                // For simplicity, assume ST(1)
                try code.append(allocator, 0xDF);
                try code.append(allocator, 0xF1);
            } else {
                // Default to ST(1)
                try code.append(allocator, 0xDF);
                try code.append(allocator, 0xF1);
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FUCOM")) {
            // FUCOM - Unordered compare ST0 with ST(i)
            try code.append(allocator, 0xDD);
            try code.append(allocator, 0xE1); // FUCOM ST(1)
        }
        else if (std.mem.eql(u8, mnemonic, "FUCOMP")) {
            // FUCOMP - Unordered compare and pop
            try code.append(allocator, 0xDD);
            try code.append(allocator, 0xE9); // FUCOMP ST(1)
        }
        else if (std.mem.eql(u8, mnemonic, "FUCOMPP")) {
            // FUCOMPP - Unordered compare and pop twice
            try code.append(allocator, 0xDA);
            try code.append(allocator, 0xE9);
        }
        else if (std.mem.eql(u8, mnemonic, "FTST")) {
            // FTST - Test ST0 (compare with 0.0)
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xE4);
        }
        else if (std.mem.eql(u8, mnemonic, "FXAM")) {
            // FXAM - Examine ST0 (check type/sign)
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xE5);
        }
        
        // x87 Constant Loading
        else if (std.mem.eql(u8, mnemonic, "FLDZ")) {
            // FLDZ - Push +0.0 onto stack
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xEE);
        }
        else if (std.mem.eql(u8, mnemonic, "FLD1")) {
            // FLD1 - Push +1.0 onto stack
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xE8);
        }
        else if (std.mem.eql(u8, mnemonic, "FLDPI")) {
            // FLDPI - Push π onto stack
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xEB);
        }
        else if (std.mem.eql(u8, mnemonic, "FLDL2T")) {
            // FLDL2T - Push log2(10) onto stack
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xE9);
        }
        else if (std.mem.eql(u8, mnemonic, "FLDL2E")) {
            // FLDL2E - Push log2(e) onto stack
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xEA);
        }
        else if (std.mem.eql(u8, mnemonic, "FLDLG2")) {
            // FLDLG2 - Push log10(2) onto stack
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xEC);
        }
        else if (std.mem.eql(u8, mnemonic, "FLDLN2")) {
            // FLDLN2 - Push ln(2) onto stack
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xED);
        }
        
        // x87 Control/Status Operations
        else if (std.mem.eql(u8, mnemonic, "FLDCW")) {
            // FLDCW - Load FPU control word from memory
            if (instr.operands.len == 1 and instr.operands[0] == .memory) {
                const mem = instr.operands[0].memory;
                // FLDCW word [mem] - 0xD9 /5
                try code.append(allocator, 0xD9);
                try self.encodeModRM(5, mem, code, allocator);
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FSTCW")) {
            // FSTCW - Store FPU control word to memory (check for exceptions)
            if (instr.operands.len == 1 and instr.operands[0] == .memory) {
                const mem = instr.operands[0].memory;
                // FSTCW word [mem] - 0xD9 /7 (with wait)
                try code.append(allocator, 0x9B); // WAIT prefix
                try code.append(allocator, 0xD9);
                try self.encodeModRM(7, mem, code, allocator);
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FNSTCW")) {
            // FNSTCW - Store FPU control word to memory (no exception check)
            if (instr.operands.len == 1 and instr.operands[0] == .memory) {
                const mem = instr.operands[0].memory;
                // FNSTCW word [mem] - 0xD9 /7 (no wait)
                try code.append(allocator, 0xD9);
                try self.encodeModRM(7, mem, code, allocator);
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FSTSW")) {
            // FSTSW - Store FPU status word to memory or AX (with wait)
            if (instr.operands.len == 1) {
                const dst = instr.operands[0];
                if (dst == .memory) {
                    const mem = dst.memory;
                    // FSTSW word [mem] - 0xDD /7
                    try code.append(allocator, 0x9B); // WAIT prefix
                    try code.append(allocator, 0xDD);
                    try self.encodeModRM(7, mem, code, allocator);
                } else if (dst == .register and dst.register.id == 0) {
                    // FSTSW AX - 0x9B 0xDF 0xE0
                    try code.append(allocator, 0x9B); // WAIT prefix
                    try code.append(allocator, 0xDF);
                    try code.append(allocator, 0xE0);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FNSTSW")) {
            // FNSTSW - Store FPU status word (no wait)
            if (instr.operands.len == 1) {
                const dst = instr.operands[0];
                if (dst == .memory) {
                    const mem = dst.memory;
                    // FNSTSW word [mem] - 0xDD /7
                    try code.append(allocator, 0xDD);
                    try self.encodeModRM(7, mem, code, allocator);
                } else if (dst == .register and dst.register.id == 0) {
                    // FNSTSW AX - 0xDF 0xE0
                    try code.append(allocator, 0xDF);
                    try code.append(allocator, 0xE0);
                }
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FCLEX")) {
            // FCLEX - Clear exceptions (with wait)
            try code.append(allocator, 0x9B); // WAIT prefix
            try code.append(allocator, 0xDB);
            try code.append(allocator, 0xE2);
        }
        else if (std.mem.eql(u8, mnemonic, "FNCLEX")) {
            // FNCLEX - Clear exceptions (no wait)
            try code.append(allocator, 0xDB);
            try code.append(allocator, 0xE2);
        }
        else if (std.mem.eql(u8, mnemonic, "FINIT")) {
            // FINIT - Initialize FPU (with wait)
            try code.append(allocator, 0x9B); // WAIT prefix
            try code.append(allocator, 0xDB);
            try code.append(allocator, 0xE3);
        }
        else if (std.mem.eql(u8, mnemonic, "FNINIT")) {
            // FNINIT - Initialize FPU (no wait)
            try code.append(allocator, 0xDB);
            try code.append(allocator, 0xE3);
        }
        else if (std.mem.eql(u8, mnemonic, "FWAIT") or std.mem.eql(u8, mnemonic, "WAIT")) {
            // FWAIT/WAIT - Wait for FPU
            try code.append(allocator, 0x9B);
        }
        
        // x87 Stack Management
        else if (std.mem.eql(u8, mnemonic, "FINCSTP")) {
            // FINCSTP - Increment stack pointer
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF7);
        }
        else if (std.mem.eql(u8, mnemonic, "FDECSTP")) {
            // FDECSTP - Decrement stack pointer
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xF6);
        }
        else if (std.mem.eql(u8, mnemonic, "FFREE")) {
            // FFREE - Free ST(i) register
            if (instr.operands.len == 1 and instr.operands[0] == .register) {
                // For simplicity, assume ST(0)
                try code.append(allocator, 0xDD);
                try code.append(allocator, 0xC0);
            } else {
                // Default ST(0)
                try code.append(allocator, 0xDD);
                try code.append(allocator, 0xC0);
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FXCH")) {
            // FXCH - Exchange ST0 with ST(i)
            if (instr.operands.len == 0) {
                // FXCH ST(1)
                try code.append(allocator, 0xD9);
                try code.append(allocator, 0xC9);
            } else {
                // Default ST(1)
                try code.append(allocator, 0xD9);
                try code.append(allocator, 0xC9);
            }
        }
        else if (std.mem.eql(u8, mnemonic, "FNOP")) {
            // FNOP - FPU NOP
            try code.append(allocator, 0xD9);
            try code.append(allocator, 0xD0);
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
