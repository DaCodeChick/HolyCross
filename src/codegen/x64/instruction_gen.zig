const std = @import("std");
const ir = @import("../ir.zig");
const helpers = @import("helpers.zig");
const GenContext = helpers.GenContext;
const Patterns = helpers.Patterns;

/// Instruction generators - one function per IR instruction category
/// Control Flow Instructions
pub const ControlFlow = struct {
    pub fn genRet(ctx: *GenContext) !void {
        try Patterns.emitFunctionEpilogue(ctx);
    }

    pub fn genRetVal(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // Load return value into RAX (works for both I64 and F64 bit-patterns)
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emitComment("return value in RAX", .{});
        try Patterns.emitFunctionEpilogue(ctx);
    }

    pub fn genLabel(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.dest) {
            .label => |l| try ctx.emit("@@{d:0>2}:\n", .{l}),
            else => {},
        }
    }

    pub fn genJump(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.dest) {
            .label => |l| try ctx.emit("\tJMP\t@@{d:0>2}\n", .{l}),
            else => {},
        }
    }

    pub fn genJumpIfZero(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("jump if zero", .{});
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        switch (instr.dest) {
            .label => |l| try Patterns.emitConditionalJump(ctx, "JZ", l),
            else => {},
        }
    }

    pub fn genJumpIfNotZero(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("jump if not zero", .{});
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        switch (instr.dest) {
            .label => |l| try Patterns.emitConditionalJump(ctx, "JNZ", l),
            else => {},
        }
    }
};

/// Memory/Data Movement Instructions
pub const Memory = struct {
    pub fn genLoadConst(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.src1) {
            .constant => |c| switch (c) {
                .int => |i| {
                    try ctx.emitComment("load constant {d}", .{i});
                    try ctx.emit("\tMOV\tRAX,{d}\n", .{i});
                },
                .float => |f| {
                    try ctx.emitComment("load float {d}", .{f});
                    try ctx.emit("\tMOVQ\tRAX,{d}\n", .{@as(i64, @bitCast(f))});
                },
                .bool => |b| {
                    try ctx.emit("\tMOV\tRAX,{d}\n", .{if (b) @as(i64, 1) else @as(i64, 0)});
                },
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genLoadVar(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.src1) {
            .variable => |v| {
                try ctx.emitComment("load variable {s}", .{v});

                // Check if this is a global variable
                if (ctx.isGlobalVar(v)) {
                    // Global variable - use RIP-relative addressing
                    try ctx.emit("\tMOV\tRAX,[{s}]\t//global\n", .{v});
                } else {
                    // Local variable - use RBP-relative addressing
                    const offset = ctx.getVarOffset(v);
                    try ctx.emit("\tMOV\tRAX,[RBP-{d}]\t//{s}\n", .{ offset, v });
                }
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genStoreVar(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        switch (instr.dest) {
            .variable => |v| {
                try ctx.emitComment("store to variable {s}", .{v});

                // Check if this is a global variable
                if (ctx.isGlobalVar(v)) {
                    // Global variable - use RIP-relative addressing
                    try ctx.emit("\tMOV\t[{s}],RAX\t//global\n", .{v});
                } else {
                    // Local variable - use RBP-relative addressing
                    const offset = ctx.getVarOffset(v);
                    try ctx.emit("\tMOV\t[RBP-{d}],RAX\t//{s}\n", .{ offset, v });
                }
            },
            else => {},
        }
    }

    pub fn genMove(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("move", .{});
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genAllocLocal(ctx: *GenContext) !void {
        try ctx.emitComment("allocate local variable", .{});
    }

    pub fn genParam(ctx: *GenContext, instr: *const ir.Instruction, param_idx: u32) !void {
        // System V AMD64 ABI: First 6 integer parameters in registers
        const param_regs = [_][]const u8{ "RDI", "RSI", "RDX", "RCX", "R8", "R9" };

        switch (instr.dest) {
            .variable => |var_name| {
                try ctx.emitComment("parameter: {s}", .{var_name});

                if (param_idx < 6) {
                    // Load from register
                    const reg = param_regs[param_idx];
                    const offset = ctx.getVarOffset(var_name);
                    try ctx.emit("\tMOV\t[RBP-{d}],{s}\t//{s}\n", .{ offset, reg, var_name });
                } else {
                    // Load from stack (passed by caller)
                    // Parameters 7+ are at [rbp+16], [rbp+24], etc. (after return addr and saved rbp)
                    const stack_offset = 16 + (param_idx - 6) * 8;
                    const var_offset = ctx.getVarOffset(var_name);
                    try ctx.emit("\tMOV\tRAX,[RBP+{d}]\n", .{stack_offset});
                    try ctx.emit("\tMOV\t[RBP-{d}],RAX\t//{s}\n", .{ var_offset, var_name });
                }
            },
            else => {},
        }
    }

    pub fn genLoadAddr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.src1) {
            .variable => |v| {
                try ctx.emitComment("load address of {s}", .{v});

                if (ctx.isGlobalVar(v)) {
                    // Global variable - use LEA with RIP-relative addressing
                    try ctx.emit("\tLEA\tRAX,[{s}]\t//&{s} (global)\n", .{ v, v });
                } else {
                    // Local variable - use LEA with RBP-relative addressing
                    const offset = ctx.getVarOffset(v);
                    try ctx.emit("\tLEA\tRAX,[RBP-{d}]\t//&{s}\n", .{ offset, v });
                }
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genLoadPtr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("load from pointer", .{});
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tMOV\tRAX,[RAX]\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genStorePtr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("store to pointer", .{});
        try Patterns.loadOperand(ctx, instr.dest, "RCX");
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tMOV\t[RCX],RAX\n", .{});
    }

    pub fn genCast(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // For most HolyC casts, we just move the value (weak typing)
        // The type_hint indicates the target type but in most cases it's a reinterpretation
        if (instr.type_hint) |hint| {
            try ctx.emitComment("cast to {s}", .{hint});
        } else {
            try ctx.emitComment("cast", .{});
        }
        
        // Load source operand to RAX
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        
        // For now, most casts are just moves (reinterpretation)
        // Future: Add sign extension (MOVSX) or zero extension (MOVZX) for smaller types
        
        // Store result
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }
};

/// Arithmetic Instructions
pub const Arithmetic = struct {
    pub fn genAdd(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "ADD");
    }

    pub fn genSub(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "SUB");
    }

    pub fn genMul(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\tIMUL2\tRAX,RCX\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genDiv(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\tCQO\n", .{}); // Sign extend RAX into RDX
        try ctx.emit("\tIDIV\tRCX\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genMod(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\tCQO\n", .{});
        try ctx.emit("\tIDIV\tRCX\n", .{});
        try ctx.emit("\tMOV\tRAX,RDX\n", .{}); // Remainder in RDX
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genNeg(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tNEG\tRAX\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genFAdd(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genFloatBinaryOp(ctx, instr, "FADD");
    }

    pub fn genFSub(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genFloatBinaryOp(ctx, instr, "FSUB");
    }

    pub fn genFMul(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genFloatBinaryOp(ctx, instr, "FMUL");
    }

    pub fn genFDiv(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genFloatBinaryOp(ctx, instr, "FDIV");
    }

    pub fn genFNeg(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadFloatToST0(ctx, instr.src1);
        try ctx.emit("\tFCHS\n", .{});
        try Patterns.storeFloatFromST0(ctx, instr.dest);
    }

    fn genFloatBinaryOp(ctx: *GenContext, instr: *const ir.Instruction, op: []const u8) !void {
        // x87 FPU: load src1 to ST0, perform operation with src2 from memory
        try Patterns.loadFloatToST0(ctx, instr.src1);
        
        // Emit the FPU operation with memory operand
        switch (instr.src2) {
            .temp => |t| {
                const offset = ctx.getTempOffset(t);
                try ctx.emit("\t{s}\tU64 [RBP-{d}]\t//t{d}\n", .{ op, offset, t });
            },
            .variable => |v| {
                const offset = ctx.getVarOffset(v);
                try ctx.emit("\t{s}\tU64 [RBP-{d}]\t//{s}\n", .{ op, offset, v });
            },
            else => {
                // For constants, need to load to memory first or use ST stack
                try Patterns.loadFloatToST0(ctx, instr.src2);
                try ctx.emit("\t{s}P\tST1,ST0\n", .{op}); // Operation with pop
            },
        }
        
        try Patterns.storeFloatFromST0(ctx, instr.dest);
    }

    fn genBinaryOp(ctx: *GenContext, instr: *const ir.Instruction, op: []const u8) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\t{s}\tRAX,RCX\n", .{op});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }
};

/// Bitwise Instructions
pub const Bitwise = struct {
    pub fn genBitAnd(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "AND");
    }

    pub fn genBitOr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "OR");
    }

    pub fn genBitXor(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "XOR");
    }

    pub fn genBitNot(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tNOT\tRAX\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genShl(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\tSHL\tRAX,CL\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genShr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\tSHR\tRAX,CL\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    fn genBinaryOp(ctx: *GenContext, instr: *const ir.Instruction, op: []const u8) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\t{s}\tRAX,RCX\n", .{op});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }
};

/// Logical Instructions
pub const Logical = struct {
    pub fn genLogNot(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});
        try ctx.emit("\tSETZ\tAL\n", .{});
        try ctx.emit("\tMOVZX\tRAX,AL\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genLogAnd(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // Short-circuit evaluation: if first operand is false, result is false
        try ctx.emitComment("logical AND with short-circuit", .{});
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});

        // Generate unique labels for short-circuit
        const false_label = std.fmt.allocPrint(ctx.allocator, "@@log_and_false_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(false_label);
        const end_label = std.fmt.allocPrint(ctx.allocator, "@@log_and_end_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(end_label);

        try ctx.emit("\tJZ\t{s}\n", .{false_label});

        // First operand was true, check second
        try Patterns.loadOperand(ctx, instr.src2, "RAX");
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});
        try ctx.emit("\tJZ\t{s}\n", .{false_label});

        // Both true, result is 1
        try ctx.emit("\tMOV\tRAX,1\n", .{});
        try ctx.emit("\tJMP\t{s}\n", .{end_label});

        // One was false, result is 0
        try ctx.emit("{s}:\n", .{false_label});
        try ctx.emit("\tXOR\tRAX,RAX\n", .{});

        try ctx.emit("{s}:\n", .{end_label});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genLogOr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // Short-circuit evaluation: if first operand is true, result is true
        try ctx.emitComment("logical OR with short-circuit", .{});
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});

        // Generate unique labels for short-circuit
        const true_label = std.fmt.allocPrint(ctx.allocator, "@@log_or_true_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(true_label);
        const end_label = std.fmt.allocPrint(ctx.allocator, "@@log_or_end_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(end_label);

        try ctx.emit("\tJNZ\t{s}\n", .{true_label});

        // First operand was false, check second
        try Patterns.loadOperand(ctx, instr.src2, "RAX");
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});
        try ctx.emit("\tJNZ\t{s}\n", .{true_label});

        // Both false, result is 0
        try ctx.emit("\tXOR\tRAX,RAX\n", .{});
        try ctx.emit("\tJMP\t{s}\n", .{end_label});

        // One was true, result is 1
        try ctx.emit("{s}:\n", .{true_label});
        try ctx.emit("\tMOV\tRAX,1\n", .{});

        try ctx.emit("{s}:\n", .{end_label});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genLogXor(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // XOR: true if operands differ
        try ctx.emitComment("logical XOR", .{});
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});
        try ctx.emit("\tSETNE\tAL\n", .{}); // Set al to 1 if rax != 0
        try ctx.emit("\tMOVZX\tRAX,AL\n", .{});
        try ctx.emit("\tMOV\tRCX,RAX\n", .{}); // Save first result

        try Patterns.loadOperand(ctx, instr.src2, "RAX");
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});
        try ctx.emit("\tSETNE\tAL\n", .{});
        try ctx.emit("\tMOVZX\tRAX,AL\n", .{});

        try ctx.emit("\tXOR\tRAX,RCX\n", .{}); // XOR the boolean values
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }
};

/// Comparison Instructions
pub const Comparison = struct {
    pub fn genCmpEq(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "SETE");
    }

    pub fn genCmpNe(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "SETNE");
    }

    pub fn genCmpLt(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "SETL");
    }

    pub fn genCmpLe(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "SETLE");
    }

    pub fn genCmpGt(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "SETG");
    }

    pub fn genCmpGe(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "SETGE");
    }

    fn genComparison(ctx: *GenContext, instr: *const ir.Instruction, setcc: []const u8) !void {
        try Patterns.loadOperand(ctx, instr.src1, "RAX");
        try Patterns.loadOperand(ctx, instr.src2, "RCX");
        try ctx.emit("\tCMP\tRAX,RCX\n", .{});
        try ctx.emit("\t{s}\tAL\n", .{setcc});
        try ctx.emit("\tMOVZX\tRAX,AL\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }
};

/// Function Call Instructions
pub const Functions = struct {
    pub fn genCall(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.src1) {
            .function => |f| {
                try ctx.emitComment("call {s}", .{f});

                // System V AMD64 ABI: First 6 integer arguments in registers
                const arg_regs = [_][]const u8{ "RDI", "RSI", "RDX", "RCX", "R8", "R9" };

                // Pass arguments
                if (instr.args) |args| {
                    // Count stack arguments (7+)
                    var stack_args: usize = 0;
                    if (args.len > 6) {
                        stack_args = args.len - 6;
                    }

                    // Push stack arguments in reverse order (right-to-left)
                    if (stack_args > 0) {
                        var i: usize = args.len;
                        while (i > 6) {
                            i -= 1;
                            try Patterns.loadOperand(ctx, args[i], "RAX");
                            try ctx.emit("\tPUSH\tRAX\n", .{});
                        }
                    }

                    // Load register arguments (first 6)
                    const reg_count = @min(args.len, 6);
                    var idx: usize = 0;
                    while (idx < reg_count) : (idx += 1) {
                        try Patterns.loadOperand(ctx, args[idx], arg_regs[idx]);
                    }
                }

                // Align stack to 16 bytes before call (required by System V ABI)
                // Note: This is simplified - proper implementation needs to track stack alignment
                try ctx.emit("\tCALL\t_{s}\n", .{f});

                // Clean up stack arguments if any
                if (instr.args) |args| {
                    if (args.len > 6) {
                        const stack_bytes = (args.len - 6) * 8;
                        try ctx.emit("\tADD\tRSP,{d}\n", .{stack_bytes});
                    }
                }
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "RAX");
    }

    pub fn genPrint(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // HolyC print statement - call printf
        switch (instr.src1) {
            .string => |s| {
                try ctx.emitComment("print \"{s}\"", .{s});

                // Find string in string table
                const string_id = ctx.findStringId(s) orelse 0;

                try ctx.emit("\tLEA\tRDI,[RIP+.str{d}]\n", .{string_id});
                try ctx.emit("\tXOR\tRAX,RAX\n", .{});
                try ctx.emit("\tCALL\tprintf@PLT\n", .{});
            },
            else => {},
        }
    }
};
