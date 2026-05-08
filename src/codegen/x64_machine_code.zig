const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const templeos_bin = @import("templeos_bin.zig");

/// x64 Machine Code Generator for TempleOS/ZealOS .BIN format
/// Generates raw machine code instead of assembly text
pub const X64MachineCodeGen = struct {
    allocator: Allocator,
    bin_writer: *templeos_bin.TempleOSBinWriter,
    /// Label ID to offset mapping
    labels: std.AutoHashMap(u32, u32),
    /// Function name to offset mapping
    function_offsets: std.StringHashMap(u32),
    /// Current function being generated
    current_func: ?*const ir.Function = null,
    /// Stack layout: temp/local offset from rbp
    stack_offsets: std.AutoHashMap(u32, i32),
    
    pub fn init(allocator: Allocator, bin_writer: *templeos_bin.TempleOSBinWriter) !X64MachineCodeGen {
        return .{
            .allocator = allocator,
            .bin_writer = bin_writer,
            .labels = std.AutoHashMap(u32, u32).init(allocator),
            .function_offsets = std.StringHashMap(u32).init(allocator),
            .stack_offsets = std.AutoHashMap(u32, i32).init(allocator),
        };
    }

    pub fn deinit(self: *X64MachineCodeGen) void {
        self.labels.deinit();
        
        var func_iter = self.function_offsets.keyIterator();
        while (func_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.function_offsets.deinit();
        self.stack_offsets.deinit();
    }

    /// Generate machine code from IR module
    pub fn generateFromIR(self: *X64MachineCodeGen, module: *const ir.Module) !void {
        // Generate code for all functions
        for (module.functions.items) |*func| {
            try self.generateFunction(func);
        }

        // Find main function and set as entry point
        const main_offset = self.function_offsets.get("main") orelse return error.NoMainFunction;
        try self.bin_writer.setEntryPoint(main_offset);
    }

    fn generateFunction(self: *X64MachineCodeGen, func: *const ir.Function) !void {
        self.current_func = func;
        defer self.current_func = null;
        
        // Clear label and stack offset maps for this function
        self.labels.clearRetainingCapacity();
        self.stack_offsets.clearRetainingCapacity();

        // Record function offset
        const func_start = self.bin_writer.getCurrentOffset();
        const owned_name = try self.allocator.dupe(u8, func.name);
        try self.function_offsets.put(owned_name, func_start);

        // Calculate stack frame size
        // locals + temps, each 8 bytes, aligned to 16
        const stack_size = (func.local_count + func.temp_count) * 8;
        const aligned_stack = (stack_size + 15) & ~@as(u32, 15);

        // Assign stack offsets for temps
        var i: u32 = 0;
        while (i < func.temp_count) : (i += 1) {
            const offset = -@as(i32, @intCast((i + 1) * 8));
            try self.stack_offsets.put(i, offset);
        }

        // Function prologue
        try self.emitPrologue(aligned_stack);

        // Generate code for each basic block
        for (func.blocks.items) |*block| {
            try self.generateBlock(block);
        }

        // Function epilogue (fallthrough case)
        try self.emitEpilogue();
    }

    fn generateBlock(self: *X64MachineCodeGen, block: *const ir.BasicBlock) !void {
        // Define label for this block
        const block_offset = self.bin_writer.getCurrentOffset();
        try self.labels.put(block.id, block_offset);

        // Generate code for each instruction
        for (block.instructions.items) |*instr| {
            try self.generateInstruction(instr);
        }
    }

    fn generateInstruction(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        switch (instr.opcode) {
            .load_const => try self.genLoadConst(instr),
            .ret => try self.genRet(),
            .ret_val => try self.genRetVal(instr),
            .add => try self.genBinaryOp(instr, .add),
            .sub => try self.genBinaryOp(instr, .sub),
            .mul => try self.genMul(instr),
            .call => try self.genCall(instr),
            .label => {}, // Already handled in generateBlock
            .inline_asm => try self.genInlineAsm(instr),
            else => {
                std.debug.print("Unimplemented opcode: {s}\n", .{@tagName(instr.opcode)});
                return error.UnimplementedOpcode;
            },
        }
    }

    fn genLoadConst(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // mov [rbp+offset], immediate
        const dest_offset = try self.getTempOffset(instr.dest);
        
        switch (instr.src1) {
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // mov qword [rbp+offset], imm32
                        try self.emitBytes(&[_]u8{ 0x48, 0xC7 });
                        try self.emitModRM(0, 5, dest_offset);
                        try self.emitDword(@intCast(val));
                    } else {
                        // movabs rax, imm64; mov [rbp+offset], rax
                        try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                        try self.emitQword(@bitCast(val));
                        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
                        try self.emitModRM(0, 5, dest_offset);
                    }
                },
                else => return error.UnsupportedConstant,
            },
            else => return error.InvalidOperand,
        }
    }

    fn genRet(self: *X64MachineCodeGen) !void {
        try self.emitEpilogue();
    }

    fn genRetVal(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load return value into rax
        switch (instr.src1) {
            .temp => {
                const src_offset = try self.getTempOffset(instr.src1);
                // mov rax, [rbp+offset]
                try self.emitBytes(&[_]u8{ 0x48, 0x8B });
                try self.emitModRM(0, 5, src_offset);
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // mov eax, imm32 (zero-extends to rax)
                        try self.emitByte(0xB8);
                        try self.emitDword(@intCast(val));
                    } else {
                        // movabs rax, imm64
                        try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                        try self.emitQword(@bitCast(val));
                    }
                },
                else => return error.UnsupportedConstant,
            },
            else => return error.InvalidOperand,
        }
        try self.emitEpilogue();
    }

    fn genBinaryOp(self: *X64MachineCodeGen, instr: *const ir.Instruction, op: enum { add, sub }) !void {
        // Load src1 into rax
        try self.loadOperandToRax(instr.src1);

        // Operate with src2
        switch (instr.src2) {
            .temp => {
                const src2_offset = try self.getTempOffset(instr.src2);
                switch (op) {
                    .add => try self.emitBytes(&[_]u8{ 0x48, 0x03 }), // add rax, [rbp+offset]
                    .sub => try self.emitBytes(&[_]u8{ 0x48, 0x2B }), // sub rax, [rbp+offset]
                }
                try self.emitModRM(0, 5, src2_offset);
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -128 and val <= 127) {
                        switch (op) {
                            .add => try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xC0 }), // add rax, imm8
                            .sub => try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xE8 }), // sub rax, imm8
                        }
                        try self.emitByte(@intCast(val));
                    } else {
                        switch (op) {
                            .add => try self.emitBytes(&[_]u8{ 0x48, 0x05 }), // add rax, imm32
                            .sub => try self.emitBytes(&[_]u8{ 0x48, 0x2D }), // sub rax, imm32
                        }
                        try self.emitDword(@intCast(val));
                    }
                },
                else => return error.UnsupportedConstant,
            },
            else => return error.InvalidOperand,
        }

        // Store result in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genMul(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load src1 into rax
        const src1_offset = try self.getTempOffset(instr.src1);
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(0, 5, src1_offset);

        // imul rax, [rbp+offset]
        const src2_offset = try self.getTempOffset(instr.src2);
        try self.emitBytes(&[_]u8{ 0x48, 0x0F, 0xAF });
        try self.emitModRM(0, 5, src2_offset);

        // Store result in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genCall(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // For now, simple direct call without arguments
        // TODO: Handle arguments via calling convention

        const func_name = switch (instr.src1) {
            .function => |name| name,
            else => return error.InvalidCallTarget,
        };

        // Emit call instruction with placeholder offset
        try self.emitByte(0xE8);
        const call_site = self.bin_writer.getCurrentOffset();
        try self.emitDword(0); // Placeholder - will be patched

        // Add relocation for this call
        // For TempleOS, we need to track this as IET_REL_I32
        _ = func_name;
        _ = call_site;
        // TODO: Track function calls for relocation

        // Store return value if needed
        if (instr.dest != .none) {
            const dest_offset = try self.getTempOffset(instr.dest);
            // mov [rbp+offset], rax
            try self.emitBytes(&[_]u8{ 0x48, 0x89 });
            try self.emitModRM(0, 5, dest_offset);
        }
    }

    fn genInlineAsm(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // TODO: Implement inline assembly support
        // For now, just skip it
        _ = self;
        _ = instr;
        std.debug.print("Warning: Inline assembly not yet supported in machine code generator\n", .{});
    }

    fn emitPrologue(self: *X64MachineCodeGen, stack_size: u32) !void {
        // push rbp
        try self.emitByte(0x55);
        
        // mov rbp, rsp
        try self.emitBytes(&[_]u8{ 0x48, 0x89, 0xE5 });
        
        // sub rsp, stack_size
        if (stack_size > 0) {
            if (stack_size <= 127) {
                try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xEC });
                try self.emitByte(@intCast(stack_size));
            } else {
                try self.emitBytes(&[_]u8{ 0x48, 0x81, 0xEC });
                try self.emitDword(stack_size);
            }
        }
    }

    fn emitEpilogue(self: *X64MachineCodeGen) !void {
        // mov rsp, rbp
        try self.emitBytes(&[_]u8{ 0x48, 0x89, 0xEC });
        
        // pop rbp
        try self.emitByte(0x5D);
        
        // ret
        try self.emitByte(0xC3);
    }

    fn getTempOffset(self: *X64MachineCodeGen, operand: ir.Operand) !i32 {
        return switch (operand) {
            .temp => |t| self.stack_offsets.get(t) orelse return error.UndefinedTemp,
            else => error.InvalidOperandForOffset,
        };
    }

    /// Load an operand value into rax
    fn loadOperandToRax(self: *X64MachineCodeGen, operand: ir.Operand) !void {
        switch (operand) {
            .temp => {
                const offset = try self.getTempOffset(operand);
                // mov rax, [rbp+offset]
                try self.emitBytes(&[_]u8{ 0x48, 0x8B });
                try self.emitModRM(0, 5, offset);
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // mov eax, imm32 (zero-extends to rax)
                        try self.emitByte(0xB8);
                        try self.emitDword(@intCast(val));
                    } else {
                        // movabs rax, imm64
                        try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                        try self.emitQword(@bitCast(val));
                    }
                },
                else => return error.UnsupportedConstant,
            },
            else => return error.InvalidOperand,
        }
    }

    fn emitByte(self: *X64MachineCodeGen, byte: u8) !void {
        try self.bin_writer.appendCode(&[_]u8{byte});
    }

    fn emitBytes(self: *X64MachineCodeGen, bytes: []const u8) !void {
        try self.bin_writer.appendCode(bytes);
    }

    fn emitDword(self: *X64MachineCodeGen, val: u32) !void {
        const bytes = std.mem.toBytes(val);
        try self.emitBytes(&bytes);
    }

    fn emitQword(self: *X64MachineCodeGen, val: u64) !void {
        const bytes = std.mem.toBytes(val);
        try self.emitBytes(&bytes);
    }

    /// Emit ModR/M byte with SIB for [rbp+disp] addressing
    fn emitModRM(self: *X64MachineCodeGen, reg: u8, base: u8, disp: i32) !void {
        if (disp >= -128 and disp <= 127) {
            // ModR/M: mod=01 (disp8), reg, r/m=base
            try self.emitByte(0x40 | (reg << 3) | base);
            try self.emitByte(@bitCast(@as(i8, @intCast(disp))));
        } else {
            // ModR/M: mod=10 (disp32), reg, r/m=base
            try self.emitByte(0x80 | (reg << 3) | base);
            try self.emitDword(@bitCast(disp));
        }
    }
};
