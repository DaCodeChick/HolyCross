const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const templeos_bin = @import("templeos_bin.zig");
const elf_writer = @import("elf_writer.zig");

/// Generic code buffer interface - works with both ELF and TempleOS writers
pub const CodeBuffer = union(enum) {
    templeos: *templeos_bin.TempleOSBinWriter,
    elf: *elf_writer.ELFWriter,
    
    pub fn appendCode(self: CodeBuffer, bytes: []const u8) !void {
        switch (self) {
            .templeos => |writer| try writer.appendCode(bytes),
            .elf => |writer| try writer.appendCode(bytes),
        }
    }
    
    pub fn getCurrentOffset(self: CodeBuffer) u32 {
        return switch (self) {
            .templeos => |writer| writer.getCurrentOffset(),
            .elf => |writer| writer.getCurrentOffset(),
        };
    }
    
    pub fn setEntryPoint(self: CodeBuffer, offset: u32) !void {
        switch (self) {
            .templeos => |writer| try writer.setEntryPoint(offset),
            .elf => |writer| try writer.setEntryPoint(offset),
        }
    }
    
    pub fn getCodeItems(self: CodeBuffer) []u8 {
        return switch (self) {
            .templeos => |writer| writer.code.items,
            .elf => |writer| writer.code.items,
        };
    }
    
    pub fn patchByte(self: CodeBuffer, offset: u32, value: u8) void {
        switch (self) {
            .templeos => |writer| writer.code.items[offset] = value,
            .elf => |writer| writer.code.items[offset] = value,
        }
    }
};

/// x64 Machine Code Generator
/// Generates raw machine code for both TempleOS and native Linux
pub const X64MachineCodeGen = struct {
    allocator: Allocator,
    code_buffer: CodeBuffer,
    /// Label ID to offset mapping
    labels: std.AutoHashMap(u32, u32),
    /// Function name to offset mapping
    function_offsets: std.StringHashMap(u32),
    /// Current function being generated
    current_func: ?*const ir.Function = null,
    /// Stack layout: temp/local offset from rbp
    stack_offsets: std.AutoHashMap(u32, i32),
    /// Variable name to stack offset mapping
    variable_offsets: std.StringHashMap(i32),
    /// Call sites needing relocation (call_site_offset, target_function_name)
    call_sites: std.ArrayList(CallSite),
    /// Forward jump sites needing patching (jump_offset, target_label_id)
    forward_jumps: std.ArrayList(ForwardJump),
    
    const CallSite = struct {
        offset: u32, // Offset in code where the 4-byte displacement starts
        target: []const u8, // Target function name
    };
    
    const ForwardJump = struct {
        offset: u32, // Offset in code where the 4-byte displacement starts
        target_label: u32, // Target label ID
    };
    
    pub fn init(allocator: Allocator, code_buffer: CodeBuffer) !X64MachineCodeGen {
        const empty_call_sites = try allocator.alloc(CallSite, 0);
        const empty_forward_jumps = try allocator.alloc(ForwardJump, 0);
        return .{
            .allocator = allocator,
            .code_buffer = code_buffer,
            .labels = std.AutoHashMap(u32, u32).init(allocator),
            .function_offsets = std.StringHashMap(u32).init(allocator),
            .stack_offsets = std.AutoHashMap(u32, i32).init(allocator),
            .variable_offsets = std.StringHashMap(i32).init(allocator),
            .call_sites = std.ArrayList(CallSite).fromOwnedSlice(empty_call_sites),
            .forward_jumps = std.ArrayList(ForwardJump).fromOwnedSlice(empty_forward_jumps),
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
        
        var var_iter = self.variable_offsets.keyIterator();
        while (var_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.variable_offsets.deinit();
        
        for (self.call_sites.items) |site| {
            self.allocator.free(site.target);
        }
        self.call_sites.deinit(self.allocator);
        self.forward_jumps.deinit(self.allocator);
    }

    /// Generate machine code from IR module
    pub fn generateFromIR(self: *X64MachineCodeGen, module: *const ir.Module) !void {
        // For native executables, generate _start wrapper first
        const is_native = switch (self.code_buffer) {
            .elf => true,
            .templeos => false,
        };
        
        const start_offset = if (is_native) blk: {
            const offset = try self.generateStartWrapper();
            break :blk offset;
        } else 0;
        
        // Generate code for all functions
        for (module.functions.items) |*func| {
            try self.generateFunction(func);
        }

        // Patch all call sites now that we know all function offsets
        try self.patchCallSites();

        // Set entry point
        if (is_native) {
            // For native executables, entry is _start
            try self.code_buffer.setEntryPoint(start_offset);
        } else {
            // For TempleOS, entry is main
            const main_offset = self.function_offsets.get("main") orelse return error.NoMainFunction;
            try self.code_buffer.setEntryPoint(main_offset);
        }
    }

    /// Generate _start wrapper for native executables
    /// _start calls main() and then exits with the return value
    fn generateStartWrapper(self: *X64MachineCodeGen) !u32 {
        const start_offset = self.code_buffer.getCurrentOffset();
        
        // Record the call site for main - we'll patch it later
        // CALL rel32 = E8 xx xx xx xx
        try self.code_buffer.appendCode(&[_]u8{ 0xE8, 0x00, 0x00, 0x00, 0x00 });
        const call_site_offset = self.code_buffer.getCurrentOffset() - 4;
        
        // Save the call site for later patching
        const target_name = try self.allocator.dupe(u8, "main");
        try self.call_sites.append(self.allocator, .{
            .offset = call_site_offset,
            .target = target_name,
        });
        
        // Move return value (in rax) to rdi for exit syscall
        // MOV rdi, rax = 48 89 C7
        try self.code_buffer.appendCode(&[_]u8{ 0x48, 0x89, 0xC7 });
        
        // Exit syscall: mov rax, 60; syscall
        // MOV rax, 60 = 48 C7 C0 3C 00 00 00
        try self.code_buffer.appendCode(&[_]u8{ 0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00 });
        
        // SYSCALL = 0F 05
        try self.code_buffer.appendCode(&[_]u8{ 0x0F, 0x05 });
        
        return start_offset;
    }

    fn generateFunction(self: *X64MachineCodeGen, func: *const ir.Function) !void {
        self.current_func = func;
        defer self.current_func = null;
        
        // Clear label and stack offset maps for this function
        self.labels.clearRetainingCapacity();
        self.stack_offsets.clearRetainingCapacity();
        self.forward_jumps.clearRetainingCapacity();
        
        // Clear variable offsets for this function
        var var_iter = self.variable_offsets.keyIterator();
        while (var_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.variable_offsets.clearRetainingCapacity();

        // Record function offset
        const func_start = self.code_buffer.getCurrentOffset();
        const owned_name = try self.allocator.dupe(u8, func.name);
        try self.function_offsets.put(owned_name, func_start);

        // First pass: collect parameters and variables
        const empty_params = try self.allocator.alloc([]const u8, 0);
        var param_names = std.ArrayList([]const u8).fromOwnedSlice(empty_params);
        defer param_names.deinit(self.allocator);
        
        var var_sizes = std.StringHashMap(i64).init(self.allocator);
        defer var_sizes.deinit();
        
        for (func.blocks.items) |*block| {
            for (block.instructions.items) |*instr| {
                if (instr.opcode == .param) {
                    if (instr.dest == .variable) {
                        try param_names.append(self.allocator, instr.dest.variable);
                    }
                } else if (instr.opcode == .alloc_local) {
                    if (instr.dest == .variable and instr.src1 == .constant) {
                        const var_name = instr.dest.variable;
                        const size = instr.src1.constant.int;
                        try var_sizes.put(var_name, size);
                    }
                }
            }
        }

        // Assign stack offsets
        // Layout: [rbp-8] param0, [rbp-16] param1, ..., [rbp-(p*8)] paramN-1, 
        //         [rbp-(p*8+8)] local0, ..., [rbp-(p*8+l*8)] localN-1,
        //         [rbp-(p*8+l*8+8)] temp0, ..., [rbp-total] tempM-1
        var offset: i32 = 0;
        
        // Parameters come first (will be saved from registers)
        for (param_names.items) |param_name| {
            offset -= 8;
            const owned_param_name = try self.allocator.dupe(u8, param_name);
            try self.variable_offsets.put(owned_param_name, offset);
        }
        
        // Variables (locals) come after parameters
        var var_size_iter = var_sizes.iterator();
        while (var_size_iter.next()) |entry| {
            const size: i32 = @intCast(entry.value_ptr.*);
            offset -= size;
            const owned_var_name = try self.allocator.dupe(u8, entry.key_ptr.*);
            try self.variable_offsets.put(owned_var_name, offset);
        }
        
        // Temps come after variables
        var i: u32 = 0;
        while (i < func.temp_count) : (i += 1) {
            offset -= 8;
            try self.stack_offsets.put(i, offset);
        }
        
        // Calculate aligned stack size
        const total_stack: u32 = @intCast(-offset);
        const aligned_stack = (total_stack + 15) & ~@as(u32, 15);

        // Function prologue
        try self.emitPrologue(aligned_stack);

        // Save parameters from registers to stack
        // x64 calling convention: rdi, rsi, rdx, rcx, r8, r9
        const param_count = param_names.items.len;
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
        const block_offset = self.code_buffer.getCurrentOffset();
        try self.labels.put(block.id, block_offset);
        
        // Patch any forward jumps that target this label
        try self.patchForwardJumpsToLabel(block.id);

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
            .move => try self.genMove(instr),
            .load_addr => try self.genLoadAddr(instr),
            .load_ptr => try self.genLoadPtr(instr),
            .store_ptr => try self.genStorePtr(instr),
            .alloc_local => {}, // Stack space already allocated in prologue
            .param => {}, // Parameters handled in function prologue
            .ret => try self.genRet(),
            .ret_val => try self.genRetVal(instr),
            .add => try self.genBinaryOp(instr, .add),
            .sub => try self.genBinaryOp(instr, .sub),
            .mul => try self.genMul(instr),
            .div => try self.genDiv(instr),
            .mod => try self.genMod(instr),
            .neg => try self.genNeg(instr),
            .fadd => try self.genFloatBinaryOp(instr, .fadd),
            .fsub => try self.genFloatBinaryOp(instr, .fsub),
            .fmul => try self.genFloatBinaryOp(instr, .fmul),
            .fdiv => try self.genFloatBinaryOp(instr, .fdiv),
            .fneg => try self.genFloatNeg(instr),
            .bit_and => try self.genBinaryOp(instr, .bit_and),
            .bit_or => try self.genBinaryOp(instr, .bit_or),
            .bit_xor => try self.genBinaryOp(instr, .bit_xor),
            .bit_not => try self.genBitNot(instr),
            .shl => try self.genShift(instr, .shl),
            .shr => try self.genShift(instr, .shr),
            .log_and => try self.genLogicalOp(instr, .log_and),
            .log_or => try self.genLogicalOp(instr, .log_or),
            .log_not => try self.genLogNot(instr),
            .call => try self.genCall(instr),
            .print => try self.genPrint(instr),
            .cmp_eq => try self.genComparison(instr, .eq),
            .cmp_ne => try self.genComparison(instr, .ne),
            .cmp_lt => try self.genComparison(instr, .lt),
            .cmp_le => try self.genComparison(instr, .le),
            .cmp_gt => try self.genComparison(instr, .gt),
            .cmp_ge => try self.genComparison(instr, .ge),
            .jump => try self.genJump(instr),
            .jump_if_zero => try self.genJumpIfZero(instr),
            .jump_if_not_zero => try self.genJumpIfNotZero(instr),
            .label => try self.genLabel(instr),
            .cast => try self.genCast(instr),
            .inline_asm => try self.genInlineAsm(instr),
            else => {
                std.debug.print("Unimplemented opcode: {s}\n", .{@tagName(instr.opcode)});
                return error.UnimplementedOpcode;
            },
        }
    }

    fn genLoadConst(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load immediate constant to a temp location
        const dest_offset = try self.getTempOffset(instr.dest);
        
        switch (instr.src1) {
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // mov qword [rbp+offset], imm32 (sign-extends)
                        try self.emitBytes(&[_]u8{ 0x48, 0xC7 });
                        try self.emitModRM(0, 5, dest_offset);
                        try self.emitDword(@bitCast(@as(i32, @intCast(val))));
                    } else {
                        // movabs rax, imm64; mov [rbp+offset], rax
                        try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                        try self.emitQword(@bitCast(val));
                        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
                        try self.emitModRM(0, 5, dest_offset);
                    }
                },
                .float => |val| {
                    // Store float constant using x87 FPU or direct memory store
                    const float_bits: u64 = @bitCast(val);
                    // movabs rax, float_bits
                    try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                    try self.emitQword(float_bits);
                    // mov [rbp+offset], rax
                    try self.emitBytes(&[_]u8{ 0x48, 0x89 });
                    try self.emitModRM(0, 5, dest_offset);
                },
                .bool => |val| {
                    // mov qword [rbp+offset], 0 or 1
                    try self.emitBytes(&[_]u8{ 0x48, 0xC7 });
                    try self.emitModRM(0, 5, dest_offset);
                    try self.emitDword(if (val) 1 else 0);
                },
            },
            else => return error.InvalidOperand,
        }
    }

    fn genRet(self: *X64MachineCodeGen) !void {
        try self.emitEpilogue();
    }

    fn genRetVal(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load return value into rax (for integers/pointers) or ST0 (for floats via x87 FPU)
        switch (instr.src1) {
            .temp => {
                const src_offset = try self.getTempOffset(instr.src1);
                // mov rax, [rbp+offset]
                // TODO: Need to detect if temp is float type and use FLD instead
                try self.emitBytes(&[_]u8{ 0x48, 0x8B });
                try self.emitModRM(0, 5, src_offset);
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // mov rax, imm32 (sign-extends to rax)
                        try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0 });
                        try self.emitDword(@bitCast(@as(i32, @intCast(val))));
                    } else {
                        // movabs rax, imm64
                        try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                        try self.emitQword(@bitCast(val));
                    }
                },
                .float => |val| {
                    // x87 FPU: Load float constant into ST0
                    // We need to store the float in memory first, then FLD it
                    const float_bits: u64 = @bitCast(val);
                    
                    // Push the float value onto stack at [rsp-8]
                    // sub rsp, 8
                    try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xEC, 0x08 });
                    
                    // movabs rax, float_bits
                    try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                    try self.emitQword(float_bits);
                    
                    // mov [rsp], rax (store float bits to stack)
                    try self.emitBytes(&[_]u8{ 0x48, 0x89, 0x04, 0x24 });
                    
                    // fld qword [rsp] (load double from stack into ST0)
                    try self.emitBytes(&[_]u8{ 0xDD, 0x04, 0x24 });
                    
                    // add rsp, 8 (restore stack)
                    try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xC4, 0x08 });
                },
                .bool => |val| {
                    // mov eax, 0 or 1
                    try self.emitByte(0xB8);
                    try self.emitDword(if (val) 1 else 0);
                },
            },
            .string => |str_lit| {
                // For now, return the string literal address as a pointer
                // TODO: Implement proper data section for string literals
                _ = str_lit;
                // mov rax, 0 (return null for now)
                try self.emitBytes(&[_]u8{ 0x48, 0x31, 0xC0 }); // xor rax, rax
            },
            else => return error.InvalidOperand,
        }
        try self.emitEpilogue();
    }

    fn genBinaryOp(self: *X64MachineCodeGen, instr: *const ir.Instruction, op: enum { add, sub, bit_and, bit_or, bit_xor }) !void {
        // Load src1 into rax
        try self.loadOperandToRax(instr.src1);

        // Operate with src2
        switch (instr.src2) {
            .temp => {
                const src2_offset = try self.getTempOffset(instr.src2);
                switch (op) {
                    .add => try self.emitBytes(&[_]u8{ 0x48, 0x03 }), // add rax, [rbp+offset]
                    .sub => try self.emitBytes(&[_]u8{ 0x48, 0x2B }), // sub rax, [rbp+offset]
                    .bit_and => try self.emitBytes(&[_]u8{ 0x48, 0x23 }), // and rax, [rbp+offset]
                    .bit_or => try self.emitBytes(&[_]u8{ 0x48, 0x0B }), // or rax, [rbp+offset]
                    .bit_xor => try self.emitBytes(&[_]u8{ 0x48, 0x33 }), // xor rax, [rbp+offset]
                }
                try self.emitModRM(0, 5, src2_offset);
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -128 and val <= 127) {
                        switch (op) {
                            .add => try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xC0 }), // add rax, imm8
                            .sub => try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xE8 }), // sub rax, imm8
                            .bit_and => try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xE0 }), // and rax, imm8
                            .bit_or => try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xC8 }), // or rax, imm8
                            .bit_xor => try self.emitBytes(&[_]u8{ 0x48, 0x83, 0xF0 }), // xor rax, imm8
                        }
                        try self.emitByte(@intCast(val));
                    } else if (val >= -2147483648 and val <= 2147483647) {
                        switch (op) {
                            .add => try self.emitBytes(&[_]u8{ 0x48, 0x05 }), // add rax, imm32
                            .sub => try self.emitBytes(&[_]u8{ 0x48, 0x2D }), // sub rax, imm32
                            .bit_and => try self.emitBytes(&[_]u8{ 0x48, 0x25 }), // and rax, imm32
                            .bit_or => try self.emitBytes(&[_]u8{ 0x48, 0x0D }), // or rax, imm32
                            .bit_xor => try self.emitBytes(&[_]u8{ 0x48, 0x35 }), // xor rax, imm32
                        }
                        try self.emitDword(@bitCast(@as(i32, @intCast(val))));
                    } else {
                        // For values outside i32 range, load to register first
                        try self.emitBytes(&[_]u8{ 0x49, 0xB8 }); // movabs r8, imm64
                        try self.emitQword(@bitCast(val));
                        switch (op) {
                            .add => try self.emitBytes(&[_]u8{ 0x4C, 0x01, 0xC0 }), // add rax, r8
                            .sub => try self.emitBytes(&[_]u8{ 0x4C, 0x29, 0xC0 }), // sub rax, r8
                            .bit_and => try self.emitBytes(&[_]u8{ 0x4C, 0x21, 0xC0 }), // and rax, r8
                            .bit_or => try self.emitBytes(&[_]u8{ 0x4C, 0x09, 0xC0 }), // or rax, r8
                            .bit_xor => try self.emitBytes(&[_]u8{ 0x4C, 0x31, 0xC0 }), // xor rax, r8
                        }
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
        try self.loadOperandToRax(instr.src1);

        // Load src2 into rcx
        switch (instr.src2) {
            .temp => {
                const src2_offset = try self.getTempOffset(instr.src2);
                // imul rax, [rbp+offset]
                try self.emitBytes(&[_]u8{ 0x48, 0x0F, 0xAF });
                try self.emitModRM(0, 5, src2_offset);
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // imul rax, rax, imm32
                        try self.emitBytes(&[_]u8{ 0x48, 0x69, 0xC0 });
                        try self.emitDword(@bitCast(@as(i32, @intCast(val))));
                    } else {
                        // Load large constant into rcx and multiply
                        try self.emitBytes(&[_]u8{ 0x48, 0xB9 }); // movabs rcx, imm64
                        try self.emitQword(@bitCast(val));
                        try self.emitBytes(&[_]u8{ 0x48, 0x0F, 0xAF, 0xC1 }); // imul rax, rcx
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

    fn genDiv(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Signed division: rax = rax / operand, rdx = remainder
        // idiv requires dividend in rdx:rax, divisor in memory or register
        
        // Load dividend (src1) into rax
        const src1_offset = try self.getTempOffset(instr.src1);
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(0, 5, src1_offset);
        
        // Sign-extend rax into rdx:rax (cqo instruction)
        try self.emitBytes(&[_]u8{ 0x48, 0x99 });
        
        // Load divisor (src2) into rcx
        const src2_offset = try self.getTempOffset(instr.src2);
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(1, 5, src2_offset); // rcx = 1
        
        // idiv rcx (signed divide rdx:rax by rcx, quotient in rax, remainder in rdx)
        try self.emitBytes(&[_]u8{ 0x48, 0xF7, 0xF9 });
        
        // Store quotient (rax) in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genMod(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Modulo: rdx = rax % operand
        // idiv leaves remainder in rdx
        
        // Load dividend (src1) into rax
        const src1_offset = try self.getTempOffset(instr.src1);
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(0, 5, src1_offset);
        
        // Sign-extend rax into rdx:rax (cqo instruction)
        try self.emitBytes(&[_]u8{ 0x48, 0x99 });
        
        // Load divisor (src2) into rcx
        const src2_offset = try self.getTempOffset(instr.src2);
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(1, 5, src2_offset); // rcx = 1
        
        // idiv rcx (signed divide rdx:rax by rcx, quotient in rax, remainder in rdx)
        try self.emitBytes(&[_]u8{ 0x48, 0xF7, 0xF9 });
        
        // Store remainder (rdx) in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(2, 5, dest_offset); // rdx = 2
    }

    fn genNeg(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load source into rax
        try self.loadOperandToRax(instr.src1);
        
        // neg rax (two's complement negation)
        try self.emitBytes(&[_]u8{ 0x48, 0xF7, 0xD8 });
        
        // Store result in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genFloatBinaryOp(self: *X64MachineCodeGen, instr: *const ir.Instruction, op: enum { fadd, fsub, fmul, fdiv }) !void {
        // x87 FPU binary operation: dest = src1 op src2
        // FPU uses stack-based architecture (ST0, ST1, etc.)
        
        // Load src1 into ST0
        const src1_offset = try self.getTempOffset(instr.src1);
        // fld qword [rbp+src1_offset]
        try self.emitBytes(&[_]u8{ 0xDD });
        try self.emitModRM(0, 5, src1_offset);
        
        // Load src2 and perform operation
        const src2_offset = try self.getTempOffset(instr.src2);
        switch (op) {
            .fadd => {
                // fadd qword [rbp+src2_offset]  (ST0 = ST0 + mem)
                try self.emitBytes(&[_]u8{ 0xDC });
                try self.emitModRM(0, 5, src2_offset);
            },
            .fsub => {
                // fsub qword [rbp+src2_offset]  (ST0 = ST0 - mem)
                try self.emitBytes(&[_]u8{ 0xDC });
                try self.emitModRM(4, 5, src2_offset);
            },
            .fmul => {
                // fmul qword [rbp+src2_offset]  (ST0 = ST0 * mem)
                try self.emitBytes(&[_]u8{ 0xDC });
                try self.emitModRM(1, 5, src2_offset);
            },
            .fdiv => {
                // fdiv qword [rbp+src2_offset]  (ST0 = ST0 / mem)
                try self.emitBytes(&[_]u8{ 0xDC });
                try self.emitModRM(6, 5, src2_offset);
            },
        }
        
        // Store result from ST0 to dest and pop
        const dest_offset = try self.getTempOffset(instr.dest);
        // fstp qword [rbp+dest_offset]  (store ST0 to memory and pop)
        try self.emitBytes(&[_]u8{ 0xDD });
        try self.emitModRM(3, 5, dest_offset);
    }

    fn genFloatNeg(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // x87 FPU negation: dest = -src
        
        // Load src into ST0
        const src_offset = try self.getTempOffset(instr.src1);
        // fld qword [rbp+src_offset]
        try self.emitBytes(&[_]u8{ 0xDD });
        try self.emitModRM(0, 5, src_offset);
        
        // fchs (change sign of ST0)
        try self.emitBytes(&[_]u8{ 0xD9, 0xE0 });
        
        // Store result from ST0 to dest and pop
        const dest_offset = try self.getTempOffset(instr.dest);
        // fstp qword [rbp+dest_offset]
        try self.emitBytes(&[_]u8{ 0xDD });
        try self.emitModRM(3, 5, dest_offset);
    }

    fn genBitNot(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load source into rax
        try self.loadOperandToRax(instr.src1);
        
        // not rax (one's complement, bitwise NOT)
        try self.emitBytes(&[_]u8{ 0x48, 0xF7, 0xD0 });
        
        // Store result in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genLogNot(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Logical NOT: !x = (x == 0) ? 1 : 0
        // Load source into rax
        try self.loadOperandToRax(instr.src1);
        
        // test rax, rax (set flags based on rax)
        try self.emitBytes(&[_]u8{ 0x48, 0x85, 0xC0 });
        
        // sete al (set al to 1 if zero flag is set, 0 otherwise)
        try self.emitBytes(&[_]u8{ 0x0F, 0x94, 0xC0 });
        
        // movzx rax, al (zero-extend al to rax)
        try self.emitBytes(&[_]u8{ 0x48, 0x0F, 0xB6, 0xC0 });
        
        // Store result in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genMove(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Simple move: dest = src
        try self.loadOperandToRax(instr.src1);
        
        // Store in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genLogicalOp(self: *X64MachineCodeGen, instr: *const ir.Instruction, op: enum { log_and, log_or }) !void {
        // Logical operations need short-circuit evaluation
        // For &&: if left is 0, result is 0; otherwise result is (right != 0)
        // For ||: if left is non-zero, result is 1; otherwise result is (right != 0)
        
        // Load src1 into rax
        try self.loadOperandToRax(instr.src1);
        
        // test rax, rax
        try self.emitBytes(&[_]u8{ 0x48, 0x85, 0xC0 });
        
        const dest_offset = try self.getTempOffset(instr.dest);
        
        switch (op) {
            .log_and => {
                // For &&: if rax is 0, jump to short-circuit (result = 0)
                // je short_circuit (jump if zero)
                try self.emitBytes(&[_]u8{ 0x74, 0x00 }); // je rel8, offset patched later
                const je_offset = self.code_buffer.getCurrentOffset() - 1;
                
                // Load src2 into rax
                try self.loadOperandToRax(instr.src2);
                
                // test rax, rax
                try self.emitBytes(&[_]u8{ 0x48, 0x85, 0xC0 });
                
                // setne al (set al to 1 if not zero)
                try self.emitBytes(&[_]u8{ 0x0F, 0x95, 0xC0 });
                
                // movzx rax, al
                try self.emitBytes(&[_]u8{ 0x48, 0x0F, 0xB6, 0xC0 });
                
                // jmp done
                try self.emitBytes(&[_]u8{ 0xEB, 0x00 }); // jmp rel8
                const jmp_offset = self.code_buffer.getCurrentOffset() - 1;
                
                // short_circuit: xor rax, rax (set rax to 0)
                const short_circuit_offset = self.code_buffer.getCurrentOffset();
                const je_displacement: i8 = @intCast(@as(i32, @intCast(short_circuit_offset)) - @as(i32, @intCast(je_offset)) - 1);
                self.code_buffer.patchByte(je_offset, @bitCast(je_displacement));
                
                try self.emitBytes(&[_]u8{ 0x48, 0x31, 0xC0 }); // xor rax, rax
                
                // done:
                const done_offset = self.code_buffer.getCurrentOffset();
                const jmp_displacement: i8 = @intCast(@as(i32, @intCast(done_offset)) - @as(i32, @intCast(jmp_offset)) - 1);
                self.code_buffer.patchByte(jmp_offset, @bitCast(jmp_displacement));
            },
            .log_or => {
                // For ||: if rax is non-zero, jump to set_true (result = 1)
                // jne set_true (jump if not zero)
                try self.emitBytes(&[_]u8{ 0x75, 0x00 }); // jne rel8
                const jne_offset = self.code_buffer.getCurrentOffset() - 1;
                
                // Load src2 into rax
                try self.loadOperandToRax(instr.src2);
                
                // test rax, rax
                try self.emitBytes(&[_]u8{ 0x48, 0x85, 0xC0 });
                
                // setne al (set al to 1 if not zero)
                try self.emitBytes(&[_]u8{ 0x0F, 0x95, 0xC0 });
                
                // movzx rax, al
                try self.emitBytes(&[_]u8{ 0x48, 0x0F, 0xB6, 0xC0 });
                
                // jmp done
                try self.emitBytes(&[_]u8{ 0xEB, 0x00 }); // jmp rel8
                const jmp_offset = self.code_buffer.getCurrentOffset() - 1;
                
                // set_true: mov rax, 1
                const set_true_offset = self.code_buffer.getCurrentOffset();
                const jne_displacement: i8 = @intCast(@as(i32, @intCast(set_true_offset)) - @as(i32, @intCast(jne_offset)) - 1);
                self.code_buffer.patchByte(jne_offset, @bitCast(jne_displacement));
                
                try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00 }); // mov rax, 1
                
                // done:
                const done_offset = self.code_buffer.getCurrentOffset();
                const jmp_displacement: i8 = @intCast(@as(i32, @intCast(done_offset)) - @as(i32, @intCast(jmp_offset)) - 1);
                self.code_buffer.patchByte(jmp_offset, @bitCast(jmp_displacement));
            },
        }
        
        // Store result in dest
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genShift(self: *X64MachineCodeGen, instr: *const ir.Instruction, op: enum { shl, shr }) !void {
        // Load src1 into rax
        const src1_offset = try self.getTempOffset(instr.src1);
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(0, 5, src1_offset);
        
        // Load shift amount into rcx (x64 requires shift amount in cl)
        switch (instr.src2) {
            .temp => {
                const src2_offset = try self.getTempOffset(instr.src2);
                try self.emitBytes(&[_]u8{ 0x48, 0x8B });
                try self.emitModRM(1, 5, src2_offset); // rcx = 1
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    // mov cl, imm8
                    try self.emitBytes(&[_]u8{ 0xB1 });
                    try self.emitByte(@intCast(val & 0xFF));
                },
                else => return error.UnsupportedConstant,
            },
            else => return error.InvalidOperand,
        }
        
        // Shift rax by cl
        switch (op) {
            .shl => try self.emitBytes(&[_]u8{ 0x48, 0xD3, 0xE0 }), // shl rax, cl
            .shr => try self.emitBytes(&[_]u8{ 0x48, 0xD3, 0xE8 }), // shr rax, cl (logical shift)
        }
        
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
                            if (val >= -2147483648 and val <= 2147483647) {
                                const imm32 = @as(i32, @intCast(val));
                                if (i < 4) {
                                    // rdi, rsi, rdx, rcx - use simple encoding
                                    try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0 | (arg_regs[i] & 7) });
                                    try self.emitDword(@bitCast(imm32));
                                } else {
                                    // r8, r9 - need REX.B
                                    try self.emitBytes(&[_]u8{ 0x49, 0xC7, 0xC0 | (arg_regs[i] & 7) });
                                    try self.emitDword(@bitCast(imm32));
                                }
                            } else {
                                // movabs reg, imm64
                                if (i < 4) {
                                    try self.emitBytes(&[_]u8{ 0x48, 0xB8 + (arg_regs[i] & 7) });
                                } else {
                                    try self.emitBytes(&[_]u8{ 0x49, 0xB8 + (arg_regs[i] & 7) });
                                }
                                try self.emitQword(@bitCast(val));
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
        const call_site = self.code_buffer.getCurrentOffset();
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

    fn genPrint(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Print a string using write syscall (Linux)
        // syscall number 1 (write) with fd=1 (stdout)
        
        const string_ptr = switch (instr.src1) {
            .string => |s| s,
            else => return error.InvalidPrintOperand,
        };
        
        // For machine code generation, proper string literal handling needs data section support
        // This is a stub implementation that emits valid code but doesn't actually print
        
        // mov rdi, 1 (stdout)
        try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC7, 0x01, 0x00, 0x00, 0x00 });
        
        // mov rax, 1 (sys_write)
        try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00 });
        
        // syscall (will fail with EFAULT but won't crash)
        try self.emitBytes(&[_]u8{ 0x0F, 0x05 });
        
        // TODO: Implement proper string literal storage and addressing
        // For now, just suppress the unused warning
        _ = string_ptr;
        
        std.debug.print("Warning: Print opcode not fully implemented in machine code gen yet\n", .{});
    }

    fn genInlineAsm(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // TODO: Implement inline assembly support
        // For now, just skip it
        _ = self;
        _ = instr;
        std.debug.print("Warning: Inline assembly not yet supported in machine code generator\n", .{});
    }

    fn genLoadVar(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load a variable into a temp
        const var_name = switch (instr.src1) {
            .variable => |name| name,
            else => return error.InvalidVariableOperand,
        };
        
        const var_offset = self.variable_offsets.get(var_name) orelse {
            std.debug.print("Error: Undefined variable '{s}'\n", .{var_name});
            return error.UndefinedVariable;
        };
        
        const dest_offset = try self.getTempOffset(instr.dest);
        
        // mov rax, [rbp+var_offset]
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(0, 5, var_offset);
        
        // mov [rbp+dest_offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genStoreVar(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Store a temp/constant into a variable location
        const var_name = switch (instr.dest) {
            .variable => |name| name,
            else => return error.InvalidVariableOperand,
        };
        
        const var_offset = self.variable_offsets.get(var_name) orelse {
            std.debug.print("Error: Undefined variable '{s}'\n", .{var_name});
            return error.UndefinedVariable;
        };
        
        // Load source value into rax
        switch (instr.src1) {
            .temp => {
                const src_offset = try self.getTempOffset(instr.src1);
                // mov rax, [rbp+src_offset]
                try self.emitBytes(&[_]u8{ 0x48, 0x8B });
                try self.emitModRM(0, 5, src_offset);
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // mov rax, imm32 (sign-extends to rax)
                        try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0 });
                        try self.emitDword(@bitCast(@as(i32, @intCast(val))));
                    } else {
                        // movabs rax, imm64
                        try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                        try self.emitQword(@bitCast(val));
                    }
                },
                .float => |val| {
                    // Load float constant bits into rax
                    const float_bits: u64 = @bitCast(val);
                    // movabs rax, float_bits
                    try self.emitBytes(&[_]u8{ 0x48, 0xB8 });
                    try self.emitQword(float_bits);
                },
                .bool => |val| {
                    // mov rax, 0 or 1
                    try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0 });
                    try self.emitDword(if (val) 1 else 0);
                },
            },
            else => return error.InvalidStoreSource,
        }
        
        // mov [rbp+var_offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, var_offset);
    }

    fn genLoadAddr(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load address of a variable into a temp using LEA
        const var_name = switch (instr.src1) {
            .variable => |name| name,
            else => return error.InvalidVariableOperand,
        };
        
        const var_offset = self.variable_offsets.get(var_name) orelse {
            std.debug.print("Error: Undefined variable '{s}'\n", .{var_name});
            return error.UndefinedVariable;
        };
        
        const dest_offset = try self.getTempOffset(instr.dest);
        
        // lea rax, [rbp+var_offset]
        try self.emitBytes(&[_]u8{ 0x48, 0x8D });
        try self.emitModRM(0, 5, var_offset);
        
        // mov [rbp+dest_offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genLoadPtr(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load value from pointer: dest = *ptr
        // Load pointer address into rax
        try self.loadOperandToRax(instr.src1);
        
        // Load value from [rax] into rax
        // mov rax, [rax]
        try self.emitBytes(&[_]u8{ 0x48, 0x8B, 0x00 });
        
        // Store to destination
        const dest_offset = try self.getTempOffset(instr.dest);
        // mov [rbp+dest_offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genStorePtr(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Store value to pointer: *ptr = src
        // Load pointer address into rcx
        const dest_offset = try self.getTempOffset(instr.dest);
        // mov rcx, [rbp+dest_offset]
        try self.emitBytes(&[_]u8{ 0x48, 0x8B });
        try self.emitModRM(1, 5, dest_offset); // rcx = 1
        
        // Load source value into rax
        try self.loadOperandToRax(instr.src1);
        
        // Store rax to [rcx]
        // mov [rcx], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89, 0x01 });
    }

    fn genComparison(self: *X64MachineCodeGen, instr: *const ir.Instruction, cond: enum { eq, ne, lt, le, gt, ge }) !void {
        // Load src1 into rax
        try self.loadOperandToRax(instr.src1);
        
        // Load src2 into rcx
        switch (instr.src2) {
            .temp => {
                const src2_offset = try self.getTempOffset(instr.src2);
                // mov rcx, [rbp+offset]
                try self.emitBytes(&[_]u8{ 0x48, 0x8B });
                try self.emitModRM(1, 5, src2_offset); // rcx = 1
            },
            .constant => |c| switch (c) {
                .int => |val| {
                    if (val >= -2147483648 and val <= 2147483647) {
                        // mov rcx, imm32 (sign-extends to rcx)
                        try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC1 });
                        try self.emitDword(@bitCast(@as(i32, @intCast(val))));
                    } else {
                        // movabs rcx, imm64
                        try self.emitBytes(&[_]u8{ 0x48, 0xB9 });
                        try self.emitQword(@bitCast(val));
                    }
                },
                else => return error.UnsupportedConstant,
            },
            else => return error.InvalidOperand,
        }
        
        // cmp rax, rcx
        try self.emitBytes(&[_]u8{ 0x48, 0x39, 0xC8 });
        
        // setCC al (set AL based on condition)
        switch (cond) {
            .eq => try self.emitBytes(&[_]u8{ 0x0F, 0x94, 0xC0 }), // sete al
            .ne => try self.emitBytes(&[_]u8{ 0x0F, 0x95, 0xC0 }), // setne al
            .lt => try self.emitBytes(&[_]u8{ 0x0F, 0x9C, 0xC0 }), // setl al
            .le => try self.emitBytes(&[_]u8{ 0x0F, 0x9E, 0xC0 }), // setle al
            .gt => try self.emitBytes(&[_]u8{ 0x0F, 0x9F, 0xC0 }), // setg al
            .ge => try self.emitBytes(&[_]u8{ 0x0F, 0x9D, 0xC0 }), // setge al
        }
        
        // movzx rax, al (zero-extend AL to RAX)
        try self.emitBytes(&[_]u8{ 0x48, 0x0F, 0xB6, 0xC0 });
        
        // Store result in dest
        const dest_offset = try self.getTempOffset(instr.dest);
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genLabel(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        const label_id = switch (instr.dest) {
            .label => |l| l,
            else => return error.InvalidLabelOperand,
        };
        
        // Define the label at the current code offset
        const current_offset = self.code_buffer.getCurrentOffset();
        try self.labels.put(label_id, current_offset);
        
        // Patch any forward jumps that target this label
        try self.patchForwardJumpsToLabel(label_id);
    }

    fn genCast(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // For most HolyC casts, we just move the value (weak typing)
        // This is a reinterpretation cast in most cases
        // Future: Add sign/zero extension for narrowing/widening integer casts
        
        // Load source value into rax
        try self.loadOperandToRax(instr.src1);
        
        // Store to destination
        const dest_offset = try self.getTempOffset(instr.dest);
        // mov [rbp+offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, dest_offset);
    }

    fn genJump(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        const label_id = switch (instr.dest) {
            .label => |l| l,
            else => return error.InvalidJumpTarget,
        };
        
        // Check if label is already defined (backward jump)
        if (self.labels.get(label_id)) |target_offset| {
            const current_offset = self.code_buffer.getCurrentOffset();
            const next_instr = current_offset + 5; // jmp instruction is 5 bytes
            const displacement = @as(i32, @intCast(target_offset)) - @as(i32, @intCast(next_instr));
            
            // jmp rel32
            try self.emitByte(0xE9);
            try self.emitDword(@bitCast(displacement));
        } else {
            // Forward jump - emit placeholder and track for later patching
            try self.emitByte(0xE9);
            const jump_offset = self.code_buffer.getCurrentOffset();
            try self.emitDword(0); // Placeholder
            
            try self.forward_jumps.append(self.allocator, .{
                .offset = jump_offset,
                .target_label = label_id,
            });
        }
    }

    fn genJumpIfZero(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load condition into rax and test it
        try self.loadOperandToRax(instr.src1);
        
        // test rax, rax
        try self.emitBytes(&[_]u8{ 0x48, 0x85, 0xC0 });
        
        const label_id = switch (instr.dest) {
            .label => |l| l,
            else => return error.InvalidJumpTarget,
        };
        
        // Check if label is already defined (backward jump)
        if (self.labels.get(label_id)) |target_offset| {
            const current_offset = self.code_buffer.getCurrentOffset();
            const next_instr = current_offset + 6; // jz instruction is 6 bytes (0F 84 + 4-byte disp)
            const displacement = @as(i32, @intCast(target_offset)) - @as(i32, @intCast(next_instr));
            
            // jz rel32 (jump if zero flag is set)
            try self.emitBytes(&[_]u8{ 0x0F, 0x84 });
            try self.emitDword(@bitCast(displacement));
        } else {
            // Forward jump - emit placeholder and track for later patching
            try self.emitBytes(&[_]u8{ 0x0F, 0x84 });
            const jump_offset = self.code_buffer.getCurrentOffset();
            try self.emitDword(0); // Placeholder
            
            try self.forward_jumps.append(self.allocator, .{
                .offset = jump_offset,
                .target_label = label_id,
            });
        }
    }

    fn genJumpIfNotZero(self: *X64MachineCodeGen, instr: *const ir.Instruction) !void {
        // Load condition into rax and test it
        try self.loadOperandToRax(instr.src1);
        
        // test rax, rax
        try self.emitBytes(&[_]u8{ 0x48, 0x85, 0xC0 });
        
        const label_id = switch (instr.dest) {
            .label => |l| l,
            else => return error.InvalidJumpTarget,
        };
        
        // Check if label is already defined (backward jump)
        if (self.labels.get(label_id)) |target_offset| {
            const current_offset = self.code_buffer.getCurrentOffset();
            const next_instr = current_offset + 6; // jnz instruction is 6 bytes
            const displacement = @as(i32, @intCast(target_offset)) - @as(i32, @intCast(next_instr));
            
            // jnz rel32 (jump if zero flag is not set)
            try self.emitBytes(&[_]u8{ 0x0F, 0x85 });
            try self.emitDword(@bitCast(displacement));
        } else {
            // Forward jump - emit placeholder and track for later patching
            try self.emitBytes(&[_]u8{ 0x0F, 0x85 });
            const jump_offset = self.code_buffer.getCurrentOffset();
            try self.emitDword(0); // Placeholder
            
            try self.forward_jumps.append(self.allocator, .{
                .offset = jump_offset,
                .target_label = label_id,
            });
        }
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
            @memcpy(self.code_buffer.getCodeItems()[site.offset..][0..4], &disp_bytes);
        }
    }

    fn patchForwardJumpsToLabel(self: *X64MachineCodeGen, label_id: u32) !void {
        const target_offset = self.labels.get(label_id) orelse return error.UndefinedLabel;
        
        // Find and patch all forward jumps to this label
        var i: usize = 0;
        while (i < self.forward_jumps.items.len) {
            const jump = self.forward_jumps.items[i];
            if (jump.target_label == label_id) {
                // Calculate displacement
                // The offset points to the 4-byte displacement field
                // displacement = target - (offset + 4)
                const next_instr = jump.offset + 4;
                const displacement = @as(i32, @intCast(target_offset)) - @as(i32, @intCast(next_instr));
                
                // Patch the displacement in the code buffer
                const disp_bytes = std.mem.toBytes(@as(u32, @bitCast(displacement)));
                @memcpy(self.code_buffer.getCodeItems()[jump.offset..][0..4], &disp_bytes);
                
                // Remove this jump from the list (swap with last element)
                _ = self.forward_jumps.swapRemove(i);
                // Don't increment i - we need to check the swapped element
            } else {
                i += 1;
            }
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
                        // mov rax, imm32 (sign-extends to rax)
                        try self.emitBytes(&[_]u8{ 0x48, 0xC7, 0xC0 });
                        try self.emitDword(@bitCast(@as(i32, @intCast(val))));
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
        try self.code_buffer.appendCode(&[_]u8{byte});
    }

    fn emitBytes(self: *X64MachineCodeGen, bytes: []const u8) !void {
        try self.code_buffer.appendCode(bytes);
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
