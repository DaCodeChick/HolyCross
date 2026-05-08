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
    /// Call sites needing relocation (call_site_offset, target_function_name)
    call_sites: std.ArrayList(CallSite),
    
    const CallSite = struct {
        offset: u32, // Offset in code where the 4-byte displacement starts
        target: []const u8, // Target function name
    };
    
    pub fn init(allocator: Allocator, bin_writer: *templeos_bin.TempleOSBinWriter) !X64MachineCodeGen {
        const empty_call_sites = try allocator.alloc(CallSite, 0);
        return .{
            .allocator = allocator,
            .bin_writer = bin_writer,
            .labels = std.AutoHashMap(u32, u32).init(allocator),
            .function_offsets = std.StringHashMap(u32).init(allocator),
            .stack_offsets = std.AutoHashMap(u32, i32).init(allocator),
            .call_sites = std.ArrayList(CallSite).fromOwnedSlice(empty_call_sites),
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
        
        for (self.call_sites.items) |site| {
            self.allocator.free(site.target);
        }
        self.call_sites.deinit(self.allocator);
    }

    /// Generate machine code from IR module
    pub fn generateFromIR(self: *X64MachineCodeGen, module: *const ir.Module) !void {
        // Generate code for all functions
        for (module.functions.items) |*func| {
            try self.generateFunction(func);
        }

        // Patch all call sites now that we know all function offsets
        try self.patchCallSites();

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
        // parameters (saved on stack) + locals + temps, each 8 bytes, aligned to 16
        const param_count = func.param_count;
        const stack_size = (param_count + func.local_count + func.temp_count) * 8;
        const aligned_stack = (stack_size + 15) & ~@as(u32, 15);

        // Assign stack offsets
        // Parameters come first (will be saved from registers)
        var offset: i32 = -8;
        var i: u32 = 0;
        while (i < param_count) : (i += 1) {
            // Parameters use negative offsets starting at -8
            // Note: In IR, parameters might use variable names, not temp IDs
            offset -= 8;
        }
        
        // Temps come after parameters
        i = 0;
        while (i < func.temp_count) : (i += 1) {
            try self.stack_offsets.put(i, offset);
            offset -= 8;
        }

        // Function prologue
        try self.emitPrologue(aligned_stack);

        // Save parameters from registers to stack
        // x64 calling convention: rdi, rsi, rdx, rcx, r8, r9
        if (param_count >= 1) {
            // mov [rbp-8], rdi
            try self.emitBytes(&[_]u8{ 0x48, 0x89 });
            try self.emitModRM(7, 5, -8); // rdi = 7
        }
        if (param_count >= 2) {
            // mov [rbp-16], rsi
            try self.emitBytes(&[_]u8{ 0x48, 0x89 });
            try self.emitModRM(6, 5, -16); // rsi = 6
        }
        if (param_count >= 3) {
            // mov [rbp-24], rdx
            try self.emitBytes(&[_]u8{ 0x48, 0x89 });
            try self.emitModRM(2, 5, -24); // rdx = 2
        }
        if (param_count >= 4) {
            // mov [rbp-32], rcx
            try self.emitBytes(&[_]u8{ 0x48, 0x89 });
            try self.emitModRM(1, 5, -32); // rcx = 1
        }
        // TODO: Handle more params and r8, r9

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
            .load_var => try self.genLoadVar(instr),
            .store_var => try self.genStoreVar(instr),
            .param => {}, // Parameters handled in function prologue
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
        const func_name = switch (instr.src1) {
            .function => |name| name,
            else => return error.InvalidCallTarget,
        };

        // Load arguments into registers (x64 calling convention)
        // rdi, rsi, rdx, rcx, r8, r9 for first 6 integer args
        if (instr.args) |args| {
            const arg_regs = [_]u8{ 0x3F, 0x37, 0x3A, 0x39, 0x00, 0x01 }; // rdi, rsi, rdx, rcx, r8, r9
            for (args, 0..) |arg, i| {
                if (i >= 6) return error.TooManyArguments; // Stack args not yet supported
                
                switch (arg) {
                    .constant => |c| switch (c) {
                        .int => |val| {
                            // mov reg, immediate
                            if (i < 4) {
                                // rdi, rsi, rdx, rcx - use simple encoding
                                try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0 | (arg_regs[i] & 7) });
                                try self.emitDword(@intCast(val));
                            } else {
                                // r8, r9 - need REX.B
                                try self.emitBytes(&[_]u8{ 0x49, 0xC7, 0xC0 | (arg_regs[i] & 7) });
                                try self.emitDword(@intCast(val));
                            }
                        },
                        else => return error.UnsupportedArgument,
                    },
                    .temp => {
                        const src_offset = try self.getTempOffset(arg);
                        // mov reg, [rbp+offset]
                        if (i < 4) {
                            try self.emitBytes(&[_]u8{ 0x48, 0x8B });
                            try self.emitModRM(arg_regs[i] & 7, 5, src_offset);
                        } else {
                            try self.emitBytes(&[_]u8{ 0x4C, 0x8B });
                            try self.emitModRM(arg_regs[i] & 7, 5, src_offset);
                        }
                    },
                    else => return error.UnsupportedArgument,
                }
            }
        }

        // Emit call instruction with placeholder offset
        try self.emitByte(0xE8);
        const call_site = self.bin_writer.getCurrentOffset();
        try self.emitDword(0); // Placeholder - will be patched

        // Track this call site for later patching
        const owned_name = try self.allocator.dupe(u8, func_name);
        try self.call_sites.append(self.allocator, .{
            .offset = call_site,
            .target = owned_name,
        });

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

    fn genLoadVar(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load a variable (from parameter slot) into a temp
        // For now, assume variables are at fixed offsets based on param index
        // This is a simplified implementation - real one needs variable tracking
        
        // Assume src1 is a variable name, but we don't have mapping yet
        // For parameters, they're at -8, -16, -24, -32 etc
        // Just load from -8 for now as a stub
        const var_offset: i32 = -8; // TODO: Track variable offsets properly
        
        const dest_offset = try self.getTempOffset(instr.dest);
        
        // mov rax, [rbp+var_offset]
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(0, 5, var_offset);
        
        // mov [rbp+dest_offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genStoreVar(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Store a temp into a variable location
        // This is symmetric to load_var
        
        const src_offset = try self.getTempOffset(instr.src1);
        const var_offset: i32 = -8; // TODO: Track variable offsets properly
        
        // mov rax, [rbp+src_offset]
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(0, 5, src_offset);
        
        // mov [rbp+var_offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, var_offset);
    }

    fn patchCallSites(self: *X64MachineCodeGen) !void {
        // Get direct access to code buffer for patching
        for (self.call_sites.items) |site| {
            const target_offset = self.function_offsets.get(site.target) orelse {
                std.debug.print("Error: Undefined function '{s}'\n", .{site.target});
                return error.UndefinedFunction;
            };
            
            // Calculate relative offset
            // call instruction: E8 <4-byte displacement>
            // displacement = target - (site.offset + 4)
            const next_instr = site.offset + 4;
            const displacement = @as(i32, @intCast(target_offset)) - @as(i32, @intCast(next_instr));
            
            // Patch the 4-byte displacement in the code buffer
            const disp_bytes = std.mem.toBytes(@as(u32, @bitCast(displacement)));
            
            // We need to modify the code buffer directly
            // The code is in bin_writer.code.items[site.offset..site.offset+4]
            @memcpy(self.bin_writer.code.items[site.offset..][0..4], &disp_bytes);
        }
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
