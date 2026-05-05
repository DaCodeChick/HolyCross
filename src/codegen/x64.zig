const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const assembler = @import("../assembler.zig");

// Import our modular components
const helpers = @import("x64/helpers.zig");
const instruction_gen = @import("x64/instruction_gen.zig");

// Re-export for external use
pub const StackLayout = helpers.StackLayout;
const GenContext = helpers.GenContext;
const Patterns = helpers.Patterns;

/// x64 Assembly Generator
/// Clean orchestrator that delegates to specialized modules
pub const X64Generator = struct {
    allocator: Allocator,
    output: std.ArrayList(u8),
    label_counter: u32,
    current_layout: ?StackLayout,
    current_module: ?*const ir.Module,

    pub fn init(allocator: Allocator) !X64Generator {
        const empty = try allocator.alloc(u8, 0);
        return .{
            .allocator = allocator,
            .output = std.ArrayList(u8).fromOwnedSlice(empty),
            .label_counter = 0,
            .current_layout = null,
            .current_module = null,
        };
    }

    pub fn deinit(self: *X64Generator) void {
        self.output.deinit(self.allocator);
        if (self.current_layout) |*layout| {
            layout.deinit();
        }
    }

    /// Generate x64 assembly from IR module
    pub fn generateFromIR(self: *X64Generator, module: *const ir.Module) !void {
        self.current_module = module;

        try self.emitHeader();
        try self.emitDataSection(module);
        try self.emitTextSection(module);
        try self.emitMainWrapper(module);

        self.current_module = null;
    }

    fn emitHeader(self: *X64Generator) !void {
        try self.output.appendSlice(self.allocator, ".intel_syntax noprefix\n");
        try self.output.append(self.allocator, '\n');
    }

    fn emitDataSection(self: *X64Generator, module: *const ir.Module) !void {
        const has_strings = module.string_table.items.len > 0;
        const has_globals = module.globals.items.len > 0;

        if (!has_strings and !has_globals) return;

        // Emit read-only data (strings)
        if (has_strings) {
            try self.output.appendSlice(self.allocator, ".section .rodata\n");
            for (module.string_table.items, 0..) |str, i| {
                const label = try std.fmt.allocPrint(self.allocator, ".str{d}:\n", .{i});
                defer self.allocator.free(label);
                try self.output.appendSlice(self.allocator, label);
                
                const str_directive = try std.fmt.allocPrint(self.allocator, "    .string \"{s}\"\n", .{str});
                defer self.allocator.free(str_directive);
                try self.output.appendSlice(self.allocator, str_directive);
            }
            try self.output.append(self.allocator, '\n');
        }

        // Emit global variables
        if (has_globals) {
            try self.output.appendSlice(self.allocator, ".section .data\n");
            for (module.globals.items) |global| {
                const globl_directive = try std.fmt.allocPrint(self.allocator, ".globl {s}\n", .{global.name});
                defer self.allocator.free(globl_directive);
                try self.output.appendSlice(self.allocator, globl_directive);
                
                const label = try std.fmt.allocPrint(self.allocator, "{s}:\n", .{global.name});
                defer self.allocator.free(label);
                try self.output.appendSlice(self.allocator, label);

                // Emit initializer or zero
                if (global.init_value) |init_val| {
                    switch (init_val) {
                        .constant => |c| switch (c) {
                            .int => |val| {
                                const directive = try std.fmt.allocPrint(self.allocator, "    .quad {d}\n", .{val});
                                defer self.allocator.free(directive);
                                try self.output.appendSlice(self.allocator, directive);
                            },
                            .float => |val| {
                                // Convert float to hex representation for assembly
                                const int_bits: u64 = @bitCast(val);
                                const directive = try std.fmt.allocPrint(self.allocator, "    .quad 0x{x}\n", .{int_bits});
                                defer self.allocator.free(directive);
                                try self.output.appendSlice(self.allocator, directive);
                            },
                            .bool => |val| {
                                const directive = try std.fmt.allocPrint(self.allocator, "    .quad {d}\n", .{@as(i64, if (val) 1 else 0)});
                                defer self.allocator.free(directive);
                                try self.output.appendSlice(self.allocator, directive);
                            },
                        },
                        else => {
                            // Fallback to zero initialization for complex cases
                            try self.output.appendSlice(self.allocator, "    .quad 0\n");
                        },
                    }
                } else {
                    // No initializer - zero initialize
                    try self.output.appendSlice(self.allocator, "    .quad 0\n");
                }
            }
            try self.output.append(self.allocator, '\n');
        }
    }

    fn emitTextSection(self: *X64Generator, module: *const ir.Module) !void {
        try self.output.appendSlice(self.allocator, ".section .text\n");

        for (module.functions.items) |*func| {
            try self.generateFunction(func);
        }
    }

    fn emitMainWrapper(self: *X64Generator, module: *const ir.Module) !void {
        _ = self;
        _ = module;
        // Note: C's main() function is now generated by the IR builder
        // (see buildCMainFunction in ir_builder.zig)
    }

    fn generateFunction(self: *X64Generator, func: *const ir.Function) !void {
        // Calculate stack layout
        var layout = try self.calculateStackLayout(func);
        defer layout.deinit();
        self.current_layout = layout;

        // Create generation context
        var ctx = GenContext{
            .allocator = self.allocator,
            .output = &self.output,
            .current_layout = &layout,
            .current_module = self.current_module,
        };

        // Emit function prologue
        try Patterns.emitFunctionPrologue(&ctx, func.name, layout.total_size);

        // Generate code for each basic block
        for (func.blocks.items) |*block| {
            try self.generateBasicBlock(&ctx, block, func.name);
        }

        // Function epilogue (fallthrough case)
        try ctx.emit(".Lend_{s}:\n", .{func.name});
        try Patterns.emitFunctionEpilogue(&ctx);
        try ctx.emit("\n", .{});

        self.current_layout = null;
    }

    fn generateBasicBlock(self: *X64Generator, ctx: *GenContext, block: *const ir.BasicBlock, func_name: []const u8) !void {
        _ = self;
        try ctx.emit(".L{s}_block{d}:\n", .{ func_name, block.id });

        var param_idx: u32 = 0;
        for (block.instructions.items) |*instr| {
            // Track parameter index for param instructions
            if (instr.opcode == .param) {
                try generateInstructionWithParamIdx(ctx, instr, param_idx);
                param_idx += 1;
            } else {
                try generateInstruction(ctx, instr);
            }
        }
    }

    /// Calculate stack layout for a function
    fn calculateStackLayout(self: *X64Generator, func: *const ir.Function) !StackLayout {
        var layout = StackLayout.init(self.allocator);
        errdefer layout.deinit();

        var offset: i64 = 0; // Start at 0, will add size before assigning

        // Collect all variables with their sizes from alloc_local instructions
        var var_sizes = std.StringHashMap(i64).init(self.allocator);
        defer var_sizes.deinit();
        var temps = std.AutoHashMap(u32, void).init(self.allocator);
        defer temps.deinit();

        // First pass: collect variable sizes from alloc_local instructions
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

        // Second pass: collect any other variables and all temps
        for (func.blocks.items) |*block| {
            for (block.instructions.items) |*instr| {
                switch (instr.dest) {
                    .variable => |v| {
                        if (!var_sizes.contains(v)) {
                            try var_sizes.put(v, 8); // Default to 8 bytes for unknown variables
                        }
                    },
                    .temp => |t| try temps.put(t, {}),
                    else => {},
                }
                switch (instr.src1) {
                    .temp => |t| try temps.put(t, {}),
                    else => {},
                }
                switch (instr.src2) {
                    .temp => |t| try temps.put(t, {}),
                    else => {},
                }
            }
        }

        // Assign offsets to variables using their actual sizes
        // IMPORTANT: offset represents the HIGHEST address of the variable (closest to RBP)
        // For a variable of size N, it occupies [RBP-(offset+N)] through [RBP-(offset+1)]
        // But we want struct members at positive offsets to work, so we store (offset + size)
        // as the offset, making the BASE address be RBP - (offset + size)
        var var_iter = var_sizes.iterator();
        while (var_iter.next()) |entry| {
            const size = entry.value_ptr.*;
            offset += size; // Move offset to accommodate this variable
            try layout.var_offsets.put(entry.key_ptr.*, offset); // Store the offset to the base
        }

        // Assign offsets to temps (always 8 bytes each)
        // Sort temp IDs to ensure consistent allocation
        const temp_count = temps.count();
        const temp_ids = try self.allocator.alloc(u32, temp_count);
        defer self.allocator.free(temp_ids);

        {
            var temp_iter = temps.keyIterator();
            var i: usize = 0;
            while (temp_iter.next()) |temp_id| : (i += 1) {
                temp_ids[i] = temp_id.*;
            }
        }

        std.mem.sort(u32, temp_ids, {}, comptime std.sort.asc(u32));

        for (temp_ids) |temp_id| {
            try layout.temp_offsets.put(temp_id, offset);
            offset += 8;
        }

        layout.total_size = @intCast(offset);

        // Align to 16 bytes (System V ABI requirement)
        if (layout.total_size % 16 != 0) {
            layout.total_size = ((layout.total_size / 16) + 1) * 16;
        }

        return layout;
    }

    pub fn getOutput(self: *X64Generator) []const u8 {
        return self.output.items;
    }
};

/// Main instruction dispatcher - delegates to category-specific generators
fn generateInstruction(ctx: *GenContext, instr: *const ir.Instruction) !void {
    switch (instr.opcode) {
        // Control flow
        .ret => try instruction_gen.ControlFlow.genRet(ctx),
        .ret_val => try instruction_gen.ControlFlow.genRetVal(ctx),
        .label => try instruction_gen.ControlFlow.genLabel(ctx, instr),
        .jump => try instruction_gen.ControlFlow.genJump(ctx, instr),
        .jump_if_zero => try instruction_gen.ControlFlow.genJumpIfZero(ctx, instr),
        .jump_if_not_zero => try instruction_gen.ControlFlow.genJumpIfNotZero(ctx, instr),

        // Memory/Data movement
        .load_const => try instruction_gen.Memory.genLoadConst(ctx, instr),
        .load_var => try instruction_gen.Memory.genLoadVar(ctx, instr),
        .store_var => try instruction_gen.Memory.genStoreVar(ctx, instr),
        .move => try instruction_gen.Memory.genMove(ctx, instr),
        .alloc_local => try instruction_gen.Memory.genAllocLocal(ctx),
        .load_addr => try instruction_gen.Memory.genLoadAddr(ctx, instr),
        .load_ptr => try instruction_gen.Memory.genLoadPtr(ctx, instr),
        .store_ptr => try instruction_gen.Memory.genStorePtr(ctx, instr),
        .param => unreachable, // Should use generateInstructionWithParamIdx

        // Arithmetic
        .add => try instruction_gen.Arithmetic.genAdd(ctx, instr),
        .sub => try instruction_gen.Arithmetic.genSub(ctx, instr),
        .mul => try instruction_gen.Arithmetic.genMul(ctx, instr),
        .div => try instruction_gen.Arithmetic.genDiv(ctx, instr),
        .mod => try instruction_gen.Arithmetic.genMod(ctx, instr),
        .neg => try instruction_gen.Arithmetic.genNeg(ctx, instr),

        // Bitwise
        .bit_and => try instruction_gen.Bitwise.genBitAnd(ctx, instr),
        .bit_or => try instruction_gen.Bitwise.genBitOr(ctx, instr),
        .bit_xor => try instruction_gen.Bitwise.genBitXor(ctx, instr),
        .bit_not => try instruction_gen.Bitwise.genBitNot(ctx, instr),
        .shl => try instruction_gen.Bitwise.genShl(ctx, instr),
        .shr => try instruction_gen.Bitwise.genShr(ctx, instr),

        // Logical
        .log_and => try instruction_gen.Logical.genLogAnd(ctx, instr),
        .log_or => try instruction_gen.Logical.genLogOr(ctx, instr),
        .log_xor => try instruction_gen.Logical.genLogXor(ctx, instr),
        .log_not => try instruction_gen.Logical.genLogNot(ctx, instr),

        // Comparison
        .cmp_eq => try instruction_gen.Comparison.genCmpEq(ctx, instr),
        .cmp_ne => try instruction_gen.Comparison.genCmpNe(ctx, instr),
        .cmp_lt => try instruction_gen.Comparison.genCmpLt(ctx, instr),
        .cmp_le => try instruction_gen.Comparison.genCmpLe(ctx, instr),
        .cmp_gt => try instruction_gen.Comparison.genCmpGt(ctx, instr),
        .cmp_ge => try instruction_gen.Comparison.genCmpGe(ctx, instr),

        // Functions
        .call => try instruction_gen.Functions.genCall(ctx, instr),
        .print => try instruction_gen.Functions.genPrint(ctx, instr),
        
        // Inline assembly
        .inline_asm => try genInlineAsm(ctx, instr),
    }
}

/// Generate inline assembly code
fn genInlineAsm(ctx: *GenContext, instr: *const ir.Instruction) !void {
    // Get the assembly source code from the instruction
    const asm_code = switch (instr.src1) {
        .string => |s| s,
        else => return error.InvalidInlineAsmOperand,
    };
    
    // Create an x64 assembler instance
    var asm_generator = assembler.X64Assembler.init(ctx.allocator);
    defer asm_generator.deinit();
    
    // Parse the assembly code
    const instructions = asm_generator.parse(asm_code, ctx.allocator) catch |err| {
        std.debug.print("Error parsing inline assembly: {}\n", .{err});
        return err;
    };
    
    defer {
        for (instructions) |parsed_instr| {
            ctx.allocator.free(parsed_instr.operands);
        }
        ctx.allocator.free(instructions);
    }
    
    // Encode the instructions to machine code
    const machine_code = asm_generator.encode(instructions, ctx.allocator) catch |err| {
        std.debug.print("Error encoding inline assembly: {}\n", .{err});
        return err;
    };
    defer ctx.allocator.free(machine_code);
    
    // Emit the assembly code as comments for debugging
    try ctx.output.appendSlice(ctx.allocator, "    # Inline assembly block\n");
    
    // For now, we'll emit the raw bytes as .byte directives
    // A more sophisticated approach would be to emit actual assembly mnemonics
    if (machine_code.len > 0) {
        try ctx.output.appendSlice(ctx.allocator, "    .byte ");
        for (machine_code, 0..) |byte, i| {
            if (i > 0) try ctx.output.appendSlice(ctx.allocator, ", ");
            const byte_str = try std.fmt.allocPrint(ctx.allocator, "0x{x:0>2}", .{byte});
            defer ctx.allocator.free(byte_str);
            try ctx.output.appendSlice(ctx.allocator, byte_str);
        }
        try ctx.output.append(ctx.allocator, '\n');
    }
    
    try ctx.output.appendSlice(ctx.allocator, "    # End inline assembly\n");
}

/// Instruction dispatcher for param instructions (needs parameter index)
fn generateInstructionWithParamIdx(ctx: *GenContext, instr: *const ir.Instruction, param_idx: u32) !void {
    switch (instr.opcode) {
        .param => try instruction_gen.Memory.genParam(ctx, instr, param_idx),
        else => try generateInstruction(ctx, instr),
    }
}
