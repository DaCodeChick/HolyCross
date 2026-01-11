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

    pub fn genRetVal(ctx: *GenContext) !void {
        try ctx.emitComment("return value in rax", .{});
        try Patterns.emitFunctionEpilogue(ctx);
    }

    pub fn genLabel(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.dest) {
            .label => |l| try ctx.emit(".L{d}:\n", .{l}),
            else => {},
        }
    }

    pub fn genJump(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.dest) {
            .label => |l| try ctx.emit("    jmp .L{d}\n", .{l}),
            else => {},
        }
    }

    pub fn genJumpIfZero(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("jump if zero", .{});
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        switch (instr.dest) {
            .label => |l| try Patterns.emitConditionalJump(ctx, "jz", l),
            else => {},
        }
    }

    pub fn genJumpIfNotZero(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("jump if not zero", .{});
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        switch (instr.dest) {
            .label => |l| try Patterns.emitConditionalJump(ctx, "jnz", l),
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
                    try ctx.emit("    mov rax, {d}\n", .{i});
                },
                .float => |f| {
                    try ctx.emitComment("load float {d}", .{f});
                    try ctx.emit("    movq rax, {d}\n", .{@as(i64, @bitCast(f))});
                },
                .bool => |b| {
                    try ctx.emit("    mov rax, {d}\n", .{if (b) @as(i64, 1) else @as(i64, 0)});
                },
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genLoadVar(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.src1) {
            .variable => |v| {
                try ctx.emitComment("load variable {s}", .{v});

                // Check if this is a global variable
                if (ctx.isGlobalVar(v)) {
                    // Global variable - use RIP-relative addressing
                    try ctx.emit("    mov rax, [{s}]  # global\n", .{v});
                } else {
                    // Local variable - use RBP-relative addressing
                    const offset = ctx.getVarOffset(v);
                    try ctx.emit("    mov rax, [rbp-{d}]  # {s}\n", .{ offset, v });
                }
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genStoreVar(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        switch (instr.dest) {
            .variable => |v| {
                try ctx.emitComment("store to variable {s}", .{v});

                // Check if this is a global variable
                if (ctx.isGlobalVar(v)) {
                    // Global variable - use RIP-relative addressing
                    try ctx.emit("    mov [{s}], rax  # global\n", .{v});
                } else {
                    // Local variable - use RBP-relative addressing
                    const offset = ctx.getVarOffset(v);
                    try ctx.emit("    mov [rbp-{d}], rax  # {s}\n", .{ offset, v });
                }
            },
            else => {},
        }
    }

    pub fn genMove(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("move", .{});
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genAllocLocal(ctx: *GenContext) !void {
        try ctx.emitComment("allocate local variable", .{});
    }

    pub fn genParam(ctx: *GenContext, instr: *const ir.Instruction, param_idx: u32) !void {
        // System V AMD64 ABI: First 6 integer parameters in registers
        const param_regs = [_][]const u8{ "rdi", "rsi", "rdx", "rcx", "r8", "r9" };

        switch (instr.dest) {
            .variable => |var_name| {
                try ctx.emitComment("parameter: {s}", .{var_name});

                if (param_idx < 6) {
                    // Load from register
                    const reg = param_regs[param_idx];
                    const offset = ctx.getVarOffset(var_name);
                    try ctx.emit("    mov [rbp-{d}], {s}  # {s}\n", .{ offset, reg, var_name });
                } else {
                    // Load from stack (passed by caller)
                    // Parameters 7+ are at [rbp+16], [rbp+24], etc. (after return addr and saved rbp)
                    const stack_offset = 16 + (param_idx - 6) * 8;
                    const var_offset = ctx.getVarOffset(var_name);
                    try ctx.emit("    mov rax, [rbp+{d}]\n", .{stack_offset});
                    try ctx.emit("    mov [rbp-{d}], rax  # {s}\n", .{ var_offset, var_name });
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
                    try ctx.emit("    lea rax, [{s}]  # &{s} (global)\n", .{ v, v });
                } else {
                    // Local variable - use LEA with RBP-relative addressing
                    const offset = ctx.getVarOffset(v);
                    try ctx.emit("    lea rax, [rbp-{d}]  # &{s}\n", .{ offset, v });
                }
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genLoadPtr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("load from pointer", .{});
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    mov rax, [rax]\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genStorePtr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try ctx.emitComment("store to pointer", .{});
        try Patterns.loadOperand(ctx, instr.dest, "rcx");
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    mov [rcx], rax\n", .{});
    }
};

/// Arithmetic Instructions
pub const Arithmetic = struct {
    pub fn genAdd(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "add");
    }

    pub fn genSub(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "sub");
    }

    pub fn genMul(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    imul rax, rcx\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genDiv(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    cqo\n", .{}); // Sign extend RAX into RDX
        try ctx.emit("    idiv rcx\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genMod(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    cqo\n", .{});
        try ctx.emit("    idiv rcx\n", .{});
        try ctx.emit("    mov rax, rdx\n", .{}); // Remainder in RDX
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genNeg(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    neg rax\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    fn genBinaryOp(ctx: *GenContext, instr: *const ir.Instruction, op: []const u8) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    {s} rax, rcx\n", .{op});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }
};

/// Bitwise Instructions
pub const Bitwise = struct {
    pub fn genBitAnd(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "and");
    }

    pub fn genBitOr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "or");
    }

    pub fn genBitXor(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genBinaryOp(ctx, instr, "xor");
    }

    pub fn genBitNot(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    not rax\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genShl(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    shl rax, cl\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genShr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    shr rax, cl\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    fn genBinaryOp(ctx: *GenContext, instr: *const ir.Instruction, op: []const u8) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    {s} rax, rcx\n", .{op});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }
};

/// Logical Instructions
pub const Logical = struct {
    pub fn genLogNot(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    test rax, rax\n", .{});
        try ctx.emit("    setz al\n", .{});
        try ctx.emit("    movzx rax, al\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genLogAnd(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // Short-circuit evaluation: if first operand is false, result is false
        try ctx.emitComment("logical AND with short-circuit", .{});
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    test rax, rax\n", .{});

        // Generate unique labels for short-circuit
        const false_label = std.fmt.allocPrint(ctx.allocator, ".Llog_and_false_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(false_label);
        const end_label = std.fmt.allocPrint(ctx.allocator, ".Llog_and_end_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(end_label);

        try ctx.emit("    jz {s}\n", .{false_label});

        // First operand was true, check second
        try Patterns.loadOperand(ctx, instr.src2, "rax");
        try ctx.emit("    test rax, rax\n", .{});
        try ctx.emit("    jz {s}\n", .{false_label});

        // Both true, result is 1
        try ctx.emit("    mov rax, 1\n", .{});
        try ctx.emit("    jmp {s}\n", .{end_label});

        // One was false, result is 0
        try ctx.emit("{s}:\n", .{false_label});
        try ctx.emit("    xor rax, rax\n", .{});

        try ctx.emit("{s}:\n", .{end_label});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genLogOr(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // Short-circuit evaluation: if first operand is true, result is true
        try ctx.emitComment("logical OR with short-circuit", .{});
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    test rax, rax\n", .{});

        // Generate unique labels for short-circuit
        const true_label = std.fmt.allocPrint(ctx.allocator, ".Llog_or_true_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(true_label);
        const end_label = std.fmt.allocPrint(ctx.allocator, ".Llog_or_end_{d}", .{@intFromPtr(instr)}) catch unreachable;
        defer ctx.allocator.free(end_label);

        try ctx.emit("    jnz {s}\n", .{true_label});

        // First operand was false, check second
        try Patterns.loadOperand(ctx, instr.src2, "rax");
        try ctx.emit("    test rax, rax\n", .{});
        try ctx.emit("    jnz {s}\n", .{true_label});

        // Both false, result is 0
        try ctx.emit("    xor rax, rax\n", .{});
        try ctx.emit("    jmp {s}\n", .{end_label});

        // One was true, result is 1
        try ctx.emit("{s}:\n", .{true_label});
        try ctx.emit("    mov rax, 1\n", .{});

        try ctx.emit("{s}:\n", .{end_label});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genLogXor(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // XOR: true if operands differ
        try ctx.emitComment("logical XOR", .{});
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try ctx.emit("    test rax, rax\n", .{});
        try ctx.emit("    setne al\n", .{}); // Set al to 1 if rax != 0
        try ctx.emit("    movzx rax, al\n", .{});
        try ctx.emit("    mov rcx, rax\n", .{}); // Save first result

        try Patterns.loadOperand(ctx, instr.src2, "rax");
        try ctx.emit("    test rax, rax\n", .{});
        try ctx.emit("    setne al\n", .{});
        try ctx.emit("    movzx rax, al\n", .{});

        try ctx.emit("    xor rax, rcx\n", .{}); // XOR the boolean values
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }
};

/// Comparison Instructions
pub const Comparison = struct {
    pub fn genCmpEq(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "sete");
    }

    pub fn genCmpNe(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "setne");
    }

    pub fn genCmpLt(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "setl");
    }

    pub fn genCmpLe(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "setle");
    }

    pub fn genCmpGt(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "setg");
    }

    pub fn genCmpGe(ctx: *GenContext, instr: *const ir.Instruction) !void {
        try genComparison(ctx, instr, "setge");
    }

    fn genComparison(ctx: *GenContext, instr: *const ir.Instruction, setcc: []const u8) !void {
        try Patterns.loadOperand(ctx, instr.src1, "rax");
        try Patterns.loadOperand(ctx, instr.src2, "rcx");
        try ctx.emit("    cmp rax, rcx\n", .{});
        try ctx.emit("    {s} al\n", .{setcc});
        try ctx.emit("    movzx rax, al\n", .{});
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }
};

/// Function Call Instructions
pub const Functions = struct {
    pub fn genCall(ctx: *GenContext, instr: *const ir.Instruction) !void {
        switch (instr.src1) {
            .function => |f| {
                try ctx.emitComment("call {s}", .{f});

                // System V AMD64 ABI: First 6 integer arguments in registers
                const arg_regs = [_][]const u8{ "rdi", "rsi", "rdx", "rcx", "r8", "r9" };

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
                            try Patterns.loadOperand(ctx, args[i], "rax");
                            try ctx.emit("    push rax\n", .{});
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
                try ctx.emit("    call {s}\n", .{f});

                // Clean up stack arguments if any
                if (instr.args) |args| {
                    if (args.len > 6) {
                        const stack_bytes = (args.len - 6) * 8;
                        try ctx.emit("    add rsp, {d}\n", .{stack_bytes});
                    }
                }
            },
            else => {},
        }
        try Patterns.storeOperand(ctx, instr.dest, "rax");
    }

    pub fn genPrint(ctx: *GenContext, instr: *const ir.Instruction) !void {
        // HolyC print statement - call printf
        switch (instr.src1) {
            .string => |s| {
                try ctx.emitComment("print \"{s}\"", .{s});

                // Find string in string table
                const string_id = ctx.findStringId(s) orelse 0;

                try ctx.emit("    lea rdi, [rip+.str{d}]\n", .{string_id});
                try ctx.emit("    xor rax, rax\n", .{});
                try ctx.emit("    call printf@PLT\n", .{});
            },
            else => {},
        }
    }
};
