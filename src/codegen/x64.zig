const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");

/// Stack layout for a function - tracks offsets for variables and temporaries
const StackLayout = struct {
    allocator: Allocator,
    var_offsets: std.StringHashMap(i64),
    temp_offsets: std.AutoHashMap(u32, i64),
    total_size: usize,

    pub fn init(allocator: Allocator) StackLayout {
        return .{
            .allocator = allocator,
            .var_offsets = std.StringHashMap(i64).init(allocator),
            .temp_offsets = std.AutoHashMap(u32, i64).init(allocator),
            .total_size = 0,
        };
    }

    pub fn deinit(self: *StackLayout) void {
        self.var_offsets.deinit();
        self.temp_offsets.deinit();
    }

    pub fn getVarOffset(self: *const StackLayout, name: []const u8) ?i64 {
        return self.var_offsets.get(name);
    }

    pub fn getTempOffset(self: *const StackLayout, temp_id: u32) ?i64 {
        return self.temp_offsets.get(temp_id);
    }
};

/// x64 Assembly Generator
/// Translates IR to x64 assembly (AT&T syntax for GNU assembler)
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

    fn emit(self: *X64Generator, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer(self.allocator).print(fmt, args);
    }

    fn emitComment(self: *X64Generator, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer(self.allocator).print("    # ", .{});
        try self.output.writer(self.allocator).print(fmt, args);
        try self.output.writer(self.allocator).print("\n", .{});
    }

    /// Generate x64 assembly from IR module
    pub fn generateFromIR(self: *X64Generator, module: *const ir.Module) !void {
        self.current_module = module;

        // Emit header
        try self.emit(".intel_syntax noprefix\n", .{});
        try self.emit("\n", .{});

        // Emit data section (string literals)
        if (module.string_table.items.len > 0) {
            try self.emit(".section .rodata\n", .{});
            for (module.string_table.items, 0..) |str, i| {
                try self.emit(".str{d}:\n", .{i});
                try self.emit("    .string \"{s}\"\n", .{str});
            }
            try self.emit("\n", .{});
        }

        // Emit text section (code)
        try self.emit(".section .text\n", .{});

        // Generate code for each function
        for (module.functions.items) |*func| {
            try self.generateFunction(func);
        }

        // Generate C-compatible main() wrapper if Main() exists
        var has_main = false;
        for (module.functions.items) |*func| {
            if (std.mem.eql(u8, func.name, "Main")) {
                has_main = true;
                break;
            }
        }

        if (has_main) {
            try self.emit(".globl main\n", .{});
            try self.emit(".type main, @function\n", .{});
            try self.emit("main:\n", .{});
            try self.emit("    push rbp\n", .{});
            try self.emit("    mov rbp, rsp\n", .{});
            try self.emit("    call Main\n", .{});
            try self.emit("    xor rax, rax  # return 0\n", .{});
            try self.emit("    pop rbp\n", .{});
            try self.emit("    ret\n", .{});
        }

        self.current_module = null;
    }

    /// Calculate stack layout for a function
    fn calculateStackLayout(self: *X64Generator, func: *const ir.Function) !StackLayout {
        var layout = StackLayout.init(self.allocator);
        errdefer layout.deinit();

        var offset: i64 = 8; // Start at 8 (first slot after saved RBP)

        // Collect all variables and temps used in the function
        var vars = std.StringHashMap(void).init(self.allocator);
        defer vars.deinit();
        var temps = std.AutoHashMap(u32, void).init(self.allocator);
        defer temps.deinit();

        // Scan all instructions to find variables and temps
        for (func.blocks.items) |*block| {
            for (block.instructions.items) |*instr| {
                // Check dest
                switch (instr.dest) {
                    .variable => |v| try vars.put(v, {}),
                    .temp => |t| try temps.put(t, {}),
                    else => {},
                }
                // Check src1
                switch (instr.src1) {
                    .variable => |v| try vars.put(v, {}),
                    .temp => |t| try temps.put(t, {}),
                    else => {},
                }
                // Check src2
                switch (instr.src2) {
                    .variable => |v| try vars.put(v, {}),
                    .temp => |t| try temps.put(t, {}),
                    else => {},
                }
            }
        }

        // Assign offsets to variables
        var var_iter = vars.keyIterator();
        while (var_iter.next()) |var_name| {
            try layout.var_offsets.put(var_name.*, offset);
            offset += 8;
        }

        // Assign offsets to temps
        var temp_iter = temps.keyIterator();
        while (temp_iter.next()) |temp_id| {
            try layout.temp_offsets.put(temp_id.*, offset);
            offset += 8;
        }

        layout.total_size = @intCast(offset - 8);

        // Align to 16 bytes (System V ABI requirement)
        if (layout.total_size % 16 != 0) {
            layout.total_size = ((layout.total_size / 16) + 1) * 16;
        }

        return layout;
    }

    fn generateFunction(self: *X64Generator, func: *const ir.Function) !void {
        // Calculate stack layout
        var layout = try self.calculateStackLayout(func);
        defer layout.deinit();
        self.current_layout = layout;

        // Function label
        try self.emit(".globl {s}\n", .{func.name});
        try self.emit(".type {s}, @function\n", .{func.name});
        try self.emit("{s}:\n", .{func.name});

        // Function prologue
        try self.emit("    push rbp\n", .{});
        try self.emit("    mov rbp, rsp\n", .{});

        // Allocate stack space
        if (layout.total_size > 0) {
            try self.emit("    sub rsp, {d}\n", .{layout.total_size});
        }

        // Generate code for each basic block
        for (func.blocks.items) |*block| {
            try self.generateBasicBlock(block);
        }

        // Function epilogue (if not already present)
        try self.emit(".Lend_{s}:\n", .{func.name});
        try self.emit("    mov rsp, rbp\n", .{});
        try self.emit("    pop rbp\n", .{});
        try self.emit("    ret\n", .{});
        try self.emit("\n", .{});

        self.current_layout = null;
    }

    fn generateBasicBlock(self: *X64Generator, block: *const ir.BasicBlock) !void {
        try self.emit(".Lblock{d}:\n", .{block.id});

        for (block.instructions.items) |*instr| {
            try self.generateInstruction(instr);
        }
    }

    fn generateInstruction(self: *X64Generator, instr: *const ir.Instruction) !void {
        switch (instr.opcode) {
            .ret => {
                try self.emit("    mov rsp, rbp\n", .{});
                try self.emit("    pop rbp\n", .{});
                try self.emit("    ret\n", .{});
            },
            .ret_val => {
                // Value should already be in RAX
                try self.emitComment("return value in rax", .{});
                try self.emit("    mov rsp, rbp\n", .{});
                try self.emit("    pop rbp\n", .{});
                try self.emit("    ret\n", .{});
            },
            .label => {
                switch (instr.dest) {
                    .label => |l| try self.emit(".L{d}:\n", .{l}),
                    else => {},
                }
            },
            .jump => {
                switch (instr.dest) {
                    .label => |l| try self.emit("    jmp .L{d}\n", .{l}),
                    else => {},
                }
            },
            .jump_if_zero => {
                // Test src1, jump to dest if zero
                try self.emitComment("jump if zero", .{});
                try self.emitOperand(instr.src1, "rax");
                try self.emit("    test rax, rax\n", .{});
                switch (instr.dest) {
                    .label => |l| try self.emit("    jz .L{d}\n", .{l}),
                    else => {},
                }
            },
            .jump_if_not_zero => {
                try self.emitComment("jump if not zero", .{});
                try self.emitOperand(instr.src1, "rax");
                try self.emit("    test rax, rax\n", .{});
                switch (instr.dest) {
                    .label => |l| try self.emit("    jnz .L{d}\n", .{l}),
                    else => {},
                }
            },
            .load_const => {
                // Load constant into destination
                switch (instr.src1) {
                    .constant => |c| switch (c) {
                        .int => |i| {
                            try self.emitComment("load constant {d}", .{i});
                            try self.emit("    mov rax, {d}\n", .{i});
                        },
                        .float => |f| {
                            try self.emitComment("load float {d}", .{f});
                            // TODO: Proper float handling
                            try self.emit("    movq rax, {d}\n", .{@as(i64, @bitCast(f))});
                        },
                        .bool => |b| {
                            try self.emit("    mov rax, {d}\n", .{if (b) @as(i64, 1) else @as(i64, 0)});
                        },
                    },
                    else => {},
                }
                try self.storeOperand(instr.dest);
            },
            .load_var => {
                // Load variable into destination
                switch (instr.src1) {
                    .variable => |v| {
                        try self.emitComment("load variable {s}", .{v});
                        if (self.current_layout) |layout| {
                            if (layout.getVarOffset(v)) |offset| {
                                try self.emit("    mov rax, [rbp-{d}]  # {s}\n", .{ offset, v });
                            } else {
                                try self.emit("    mov rax, [rbp-8]  # {s} (unknown offset)\n", .{v});
                            }
                        } else {
                            try self.emit("    mov rax, [rbp-8]  # {s} (no layout)\n", .{v});
                        }
                    },
                    else => {},
                }
                try self.storeOperand(instr.dest);
            },
            .store_var => {
                // Store src1 into variable dest
                try self.emitOperand(instr.src1, "rax");
                switch (instr.dest) {
                    .variable => |v| {
                        try self.emitComment("store to variable {s}", .{v});
                        if (self.current_layout) |layout| {
                            if (layout.getVarOffset(v)) |offset| {
                                try self.emit("    mov [rbp-{d}], rax  # {s}\n", .{ offset, v });
                            } else {
                                try self.emit("    mov [rbp-8], rax  # {s} (unknown offset)\n", .{v});
                            }
                        } else {
                            try self.emit("    mov [rbp-8], rax  # {s} (no layout)\n", .{v});
                        }
                    },
                    else => {},
                }
            },
            .alloc_local => {
                // Local variable allocation handled in function prologue
                try self.emitComment("allocate local variable", .{});
            },
            .param => {
                // Parameter handling
                try self.emitComment("function parameter", .{});
            },
            .add => {
                try self.emitBinaryOp(instr, "add");
            },
            .sub => {
                try self.emitBinaryOp(instr, "sub");
            },
            .mul => {
                try self.emitOperand(instr.src1, "rax");
                try self.emitOperand(instr.src2, "rcx");
                try self.emit("    imul rax, rcx\n", .{});
                try self.storeOperand(instr.dest);
            },
            .div => {
                try self.emitOperand(instr.src1, "rax");
                try self.emitOperand(instr.src2, "rcx");
                try self.emit("    cqo\n", .{}); // Sign extend RAX into RDX
                try self.emit("    idiv rcx\n", .{});
                try self.storeOperand(instr.dest);
            },
            .mod => {
                try self.emitOperand(instr.src1, "rax");
                try self.emitOperand(instr.src2, "rcx");
                try self.emit("    cqo\n", .{});
                try self.emit("    idiv rcx\n", .{});
                try self.emit("    mov rax, rdx\n", .{}); // Remainder in RDX
                try self.storeOperand(instr.dest);
            },
            .bit_and => {
                try self.emitBinaryOp(instr, "and");
            },
            .bit_or => {
                try self.emitBinaryOp(instr, "or");
            },
            .bit_xor => {
                try self.emitBinaryOp(instr, "xor");
            },
            .shl => {
                try self.emitOperand(instr.src1, "rax");
                try self.emitOperand(instr.src2, "rcx");
                try self.emit("    shl rax, cl\n", .{});
                try self.storeOperand(instr.dest);
            },
            .shr => {
                try self.emitOperand(instr.src1, "rax");
                try self.emitOperand(instr.src2, "rcx");
                try self.emit("    shr rax, cl\n", .{});
                try self.storeOperand(instr.dest);
            },
            .neg => {
                try self.emitOperand(instr.src1, "rax");
                try self.emit("    neg rax\n", .{});
                try self.storeOperand(instr.dest);
            },
            .bit_not => {
                try self.emitOperand(instr.src1, "rax");
                try self.emit("    not rax\n", .{});
                try self.storeOperand(instr.dest);
            },
            .log_not => {
                try self.emitOperand(instr.src1, "rax");
                try self.emit("    test rax, rax\n", .{});
                try self.emit("    setz al\n", .{});
                try self.emit("    movzx rax, al\n", .{});
                try self.storeOperand(instr.dest);
            },
            .cmp_eq => {
                try self.emitComparison(instr, "sete");
            },
            .cmp_ne => {
                try self.emitComparison(instr, "setne");
            },
            .cmp_lt => {
                try self.emitComparison(instr, "setl");
            },
            .cmp_le => {
                try self.emitComparison(instr, "setle");
            },
            .cmp_gt => {
                try self.emitComparison(instr, "setg");
            },
            .cmp_ge => {
                try self.emitComparison(instr, "setge");
            },
            .call => {
                // Function call
                switch (instr.src1) {
                    .function => |f| {
                        try self.emitComment("call {s}", .{f});
                        // TODO: Proper argument passing (System V ABI)
                        try self.emit("    call {s}\n", .{f});
                    },
                    else => {},
                }
                try self.storeOperand(instr.dest);
            },
            .print => {
                // HolyC print statement - call printf
                switch (instr.src1) {
                    .string => |s| {
                        try self.emitComment("print \"{s}\"", .{s});
                        // Find string in string table
                        var string_id: ?usize = null;
                        if (self.current_module) |module| {
                            for (module.string_table.items, 0..) |str, i| {
                                if (std.mem.eql(u8, str, s)) {
                                    string_id = i;
                                    break;
                                }
                            }
                        }

                        if (string_id) |id| {
                            try self.emit("    lea rdi, [rip+.str{d}]\n", .{id});
                        } else {
                            try self.emit("    lea rdi, [rip+.str0]\n", .{});
                        }
                        try self.emit("    xor rax, rax\n", .{});
                        try self.emit("    call printf@PLT\n", .{});
                    },
                    else => {},
                }
            },
            else => {
                try self.emitComment("TODO: {s}", .{@tagName(instr.opcode)});
            },
        }
    }

    fn emitBinaryOp(self: *X64Generator, instr: *const ir.Instruction, op: []const u8) !void {
        try self.emitOperand(instr.src1, "rax");
        try self.emitOperand(instr.src2, "rcx");
        try self.emit("    {s} rax, rcx\n", .{op});
        try self.storeOperand(instr.dest);
    }

    fn emitComparison(self: *X64Generator, instr: *const ir.Instruction, setcc: []const u8) !void {
        try self.emitOperand(instr.src1, "rax");
        try self.emitOperand(instr.src2, "rcx");
        try self.emit("    cmp rax, rcx\n", .{});
        try self.emit("    {s} al\n", .{setcc});
        try self.emit("    movzx rax, al\n", .{});
        try self.storeOperand(instr.dest);
    }

    fn emitOperand(self: *X64Generator, operand: ir.Operand, dest_reg: []const u8) !void {
        switch (operand) {
            .none => {},
            .temp => |t| {
                // Load from temporary (on stack)
                if (self.current_layout) |layout| {
                    if (layout.getTempOffset(t)) |offset| {
                        try self.emit("    mov {s}, [rbp-{d}]  # t{d}\n", .{ dest_reg, offset, t });
                    } else {
                        try self.emit("    mov {s}, [rbp-8]  # t{d} (unknown offset)\n", .{ dest_reg, t });
                    }
                } else {
                    try self.emit("    mov {s}, [rbp-8]  # t{d} (no layout)\n", .{ dest_reg, t });
                }
            },
            .variable => |v| {
                // Load from variable (on stack)
                if (self.current_layout) |layout| {
                    if (layout.getVarOffset(v)) |offset| {
                        try self.emit("    mov {s}, [rbp-{d}]  # {s}\n", .{ dest_reg, offset, v });
                    } else {
                        try self.emit("    mov {s}, [rbp-8]  # {s} (unknown offset)\n", .{ dest_reg, v });
                    }
                } else {
                    try self.emit("    mov {s}, [rbp-8]  # {s} (no layout)\n", .{ dest_reg, v });
                }
            },
            .constant => |c| switch (c) {
                .int => |i| {
                    try self.emit("    mov {s}, {d}\n", .{ dest_reg, i });
                },
                .float => |f| {
                    try self.emit("    movq {s}, {d}\n", .{ dest_reg, @as(i64, @bitCast(f)) });
                },
                .bool => |b| {
                    try self.emit("    mov {s}, {d}\n", .{ dest_reg, if (b) @as(i64, 1) else @as(i64, 0) });
                },
            },
            .label => {},
            .function => {},
            .string => {},
        }
    }

    fn storeOperand(self: *X64Generator, operand: ir.Operand) !void {
        switch (operand) {
            .temp => |t| {
                // Store to temporary (on stack)
                if (self.current_layout) |layout| {
                    if (layout.getTempOffset(t)) |offset| {
                        try self.emit("    mov [rbp-{d}], rax  # t{d}\n", .{ offset, t });
                    } else {
                        try self.emit("    mov [rbp-8], rax  # t{d} (unknown offset)\n", .{t});
                    }
                } else {
                    try self.emit("    mov [rbp-8], rax  # t{d} (no layout)\n", .{t});
                }
            },
            .variable => |v| {
                // Store to variable (on stack)
                if (self.current_layout) |layout| {
                    if (layout.getVarOffset(v)) |offset| {
                        try self.emit("    mov [rbp-{d}], rax  # {s}\n", .{ offset, v });
                    } else {
                        try self.emit("    mov [rbp-8], rax  # {s} (unknown offset)\n", .{v});
                    }
                } else {
                    try self.emit("    mov [rbp-8], rax  # {s} (no layout)\n", .{v});
                }
            },
            else => {},
        }
    }

    pub fn getOutput(self: *X64Generator) []const u8 {
        return self.output.items;
    }
};
