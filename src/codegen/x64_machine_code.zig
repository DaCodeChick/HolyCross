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

        // First pass: collect all variables from alloc_local instructions
        var var_sizes = std.StringHashMap(i64).init(self.allocator);
        defer var_sizes.deinit();
        
        for (func.blocks.items) |*block| {
            for (block.instructions.items) |*instr| {
                if (instr.opcode == .alloc_local) {
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
        var offset: i32 = -8;
        
        // Parameters come first (will be saved from registers)
        const param_count = func.param_count;
        var i: u32 = 0;
        while (i < param_count) : (i += 1) {
            offset -= 8;
        }
        
        // Variables (locals) come after parameters
        var var_size_iter = var_sizes.iterator();
        while (var_size_iter.next()) |entry| {
            const size: i32 = @intCast(entry.value_ptr.*);
            const owned_var_name = try self.allocator.dupe(u8, entry.key_ptr.*);
            try self.variable_offsets.put(owned_var_name, offset);
            offset -= size;
        }
        
        // Temps come after variables
        i = 0;
        while (i < func.temp_count) : (i += 1) {
            try self.stack_offsets.put(i, offset);
            offset -= 8;
        }
        
        // Calculate aligned stack size
        const total_stack: u32 = @intCast(-offset);
        const aligned_stack = (total_stack + 15) & ~@as(u32, 15);

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
            .alloc_local => {}, // Stack space already allocated in prologue
            .param => {}, // Parameters handled in function prologue
            .ret => try self.genRet(),
            .ret_val => try self.genRetVal(instr),
            .add => try self.genBinaryOp(instr, .add),
            .sub => try self.genBinaryOp(instr, .sub),
            .mul => try self.genMul(instr),
            .call => try self.genCall(instr),
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
                else => return error.UnsupportedConstant,
            },
            else => return error.InvalidStoreSource,
        }
        
        // mov [rbp+var_offset], rax
        try self.emitBytes(&[_]u8{ 0x48, 0x89 });
        try self.emitModRM(0, 5, var_offset);
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
                        // mov ecx, imm32
                        try self.emitByte(0xB9);
                        try self.emitDword(@intCast(val));
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
