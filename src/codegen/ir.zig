const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../parser/ast.zig");

/// Intermediate Representation for HolyCross compiler
/// Uses a simple three-address code format that's easy to generate from AST
/// and straightforward to translate to x64 assembly
/// IR Instruction opcodes
pub const Opcode = enum {
    // Data movement
    load_const, // dest = constant
    load_var, // dest = variable
    store_var, // variable = src
    move, // dest = src

    // Arithmetic
    add, // dest = left + right
    sub, // dest = left - right
    mul, // dest = left * right
    div, // dest = left / right
    mod, // dest = left % right
    neg, // dest = -src

    // Bitwise
    bit_and, // dest = left & right
    bit_or, // dest = left | right
    bit_xor, // dest = left ^ right
    bit_not, // dest = ~src
    shl, // dest = left << right
    shr, // dest = left >> right

    // Logical
    log_and, // dest = left && right
    log_or, // dest = left || right
    log_xor, // dest = left ^^ right
    log_not, // dest = !src

    // Comparison (result is boolean)
    cmp_eq, // dest = left == right
    cmp_ne, // dest = left != right
    cmp_lt, // dest = left < right
    cmp_le, // dest = left <= right
    cmp_gt, // dest = left > right
    cmp_ge, // dest = left >= right

    // Control flow
    label, // Define a label
    jump, // Unconditional jump to label
    jump_if_zero, // Jump to label if src == 0
    jump_if_not_zero, // Jump to label if src != 0

    // Function calls
    call, // Call function
    ret, // Return from function
    ret_val, // Return value from function

    // Memory operations
    load_addr, // dest = &variable (address of variable)
    load_ptr, // dest = *ptr (load from pointer)
    store_ptr, // *ptr = src (store to pointer)

    // Type conversion
    cast, // dest = (type)src - type conversion/reinterpretation

    // Special
    print, // HolyC print statement
    alloc_local, // Allocate local variable on stack
    param, // Function parameter
    inline_asm, // Inline assembly block
};

/// Operand types for IR instructions
pub const Operand = union(enum) {
    none, // No operand
    temp: u32, // Temporary virtual register (t0, t1, etc.)
    variable: []const u8, // Named variable
    constant: Constant, // Immediate constant
    label: u32, // Label ID
    function: []const u8, // Function name
    string: []const u8, // String literal

    pub const Constant = union(enum) {
        int: i64,
        float: f64,
        bool: bool,
    };

    pub fn format(
        self: Operand,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .none => try writer.writeAll("_"),
            .temp => |t| try writer.print("t{d}", .{t}),
            .variable => |v| try writer.print("{s}", .{v}),
            .constant => |c| switch (c) {
                .int => |i| try writer.print("{d}", .{i}),
                .float => |f| try writer.print("{d}", .{f}),
                .bool => |b| try writer.writeAll(if (b) "true" else "false"),
            },
            .label => |l| try writer.print("L{d}", .{l}),
            .function => |f| try writer.print("{s}", .{f}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
        }
    }
};

/// IR Instruction
pub const Instruction = struct {
    opcode: Opcode,
    dest: Operand = .none,
    src1: Operand = .none,
    src2: Operand = .none,
    type_hint: ?[]const u8 = null, // Type info for code gen (e.g., "I64", "U8")
    args: ?[]Operand = null, // Function call arguments (for call opcode)

    pub fn deinit(self: *Instruction, allocator: Allocator) void {
        if (self.args) |args| {
            allocator.free(args);
        }
    }

    pub fn format(
        self: Instruction,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s:<16}", .{@tagName(self.opcode)});

        switch (self.opcode) {
            .label => try writer.print("{any}", .{self.dest}),
            .jump => try writer.print("{any}", .{self.dest}),
            .jump_if_zero, .jump_if_not_zero => try writer.print("{any}, {any}", .{ self.src1, self.dest }),
            .ret => {},
            .ret_val => try writer.print("{any}", .{self.src1}),
            .call => {
                try writer.print("{any}(", .{self.src1});
                if (self.args) |call_args| {
                    for (call_args, 0..) |arg, i| {
                        if (i > 0) try writer.writeAll(", ");
                        try writer.print("{any}", .{arg});
                    }
                }
                try writer.print(") -> {any}", .{self.dest});
            },
            .print => try writer.print("{any}", .{self.src1}),
            .alloc_local => try writer.print("{any}, size={any}", .{ self.dest, self.src1 }),
            .param => try writer.print("{any}", .{self.dest}),
            .inline_asm => try writer.print("asm {any}", .{self.src1}),
            .load_const, .load_var, .move, .neg, .bit_not, .log_not => {
                try writer.print("{any} = {any}", .{ self.dest, self.src1 });
            },
            else => {
                try writer.print("{any} = {any} op {any}", .{ self.dest, self.src1, self.src2 });
            },
        }

        if (self.type_hint) |hint| {
            try writer.print(" [{s}]", .{hint});
        }
    }
};

/// Basic block - sequence of instructions with single entry/exit
pub const BasicBlock = struct {
    id: u32,
    instructions: std.ArrayList(Instruction),

    pub fn init(allocator: Allocator, id: u32) !BasicBlock {
        const empty = try allocator.alloc(Instruction, 0);
        return .{
            .id = id,
            .instructions = std.ArrayList(Instruction).fromOwnedSlice(empty),
        };
    }

    pub fn deinit(self: *BasicBlock, allocator: Allocator) void {
        for (self.instructions.items) |*instr| {
            instr.deinit(allocator);
        }
        self.instructions.deinit(allocator);
    }
};

/// IR Function - contains basic blocks
pub const Function = struct {
    name: []const u8,
    blocks: std.ArrayList(BasicBlock),
    allocator: Allocator,
    param_count: u32,
    return_type: ?[]const u8,
    local_count: u32, // Number of local variables
    temp_count: u32, // Number of temporary registers used

    pub fn init(allocator: Allocator, name: []const u8) !Function {
        const empty = try allocator.alloc(BasicBlock, 0);
        return .{
            .name = name,
            .blocks = std.ArrayList(BasicBlock).fromOwnedSlice(empty),
            .allocator = allocator,
            .param_count = 0,
            .return_type = null,
            .local_count = 0,
            .temp_count = 0,
        };
    }

    pub fn deinit(self: *Function) void {
        for (self.blocks.items) |*block| {
            block.deinit(self.allocator);
        }
        self.blocks.deinit(self.allocator);
    }

    pub fn createBlock(self: *Function) !*BasicBlock {
        const id = @as(u32, @intCast(self.blocks.items.len));
        try self.blocks.append(self.allocator, try BasicBlock.init(self.allocator, id));
        return &self.blocks.items[self.blocks.items.len - 1];
    }
};

/// Global variable declaration
pub const GlobalVar = struct {
    name: []const u8,
    type_hint: ?[]const u8, // Type info (e.g., "I64", "U8")
    init_value: ?Operand, // Initial value (constant or none)
};

/// Complete IR Module
pub const Module = struct {
    allocator: Allocator,
    functions: std.ArrayList(Function),
    globals: std.ArrayList(GlobalVar), // Global variables
    string_literals: std.StringHashMap(u32), // Map string -> ID
    string_table: std.ArrayList([]const u8), // ID -> string

    pub fn init(allocator: Allocator) !Module {
        const empty_funcs = try allocator.alloc(Function, 0);
        const empty_globals = try allocator.alloc(GlobalVar, 0);
        const empty_strings = try allocator.alloc([]const u8, 0);
        return .{
            .allocator = allocator,
            .functions = std.ArrayList(Function).fromOwnedSlice(empty_funcs),
            .globals = std.ArrayList(GlobalVar).fromOwnedSlice(empty_globals),
            .string_literals = std.StringHashMap(u32).init(allocator),
            .string_table = std.ArrayList([]const u8).fromOwnedSlice(empty_strings),
        };
    }

    pub fn deinit(self: *Module) void {
        for (self.functions.items) |*func| {
            func.deinit();
        }
        self.functions.deinit(self.allocator);
        self.globals.deinit(self.allocator);
        self.string_literals.deinit();
        self.string_table.deinit(self.allocator);
    }

    pub fn createFunction(self: *Module, name: []const u8) !*Function {
        try self.functions.append(self.allocator, try Function.init(self.allocator, name));
        return &self.functions.items[self.functions.items.len - 1];
    }

    pub fn addGlobal(self: *Module, name: []const u8, type_hint: ?[]const u8, init_value: ?Operand) !void {
        try self.globals.append(self.allocator, .{
            .name = name,
            .type_hint = type_hint,
            .init_value = init_value,
        });
    }

    pub fn addStringLiteral(self: *Module, str: []const u8) !u32 {
        if (self.string_literals.get(str)) |id| {
            return id;
        }
        const id = @as(u32, @intCast(self.string_table.items.len));
        try self.string_table.append(self.allocator, str);
        try self.string_literals.put(str, id);
        return id;
    }

    /// Print IR for debugging
    pub fn print(self: *const Module, writer: anytype) !void {
        // Print string literals
        if (self.string_table.items.len > 0) {
            try writer.writeAll("=== String Literals ===\n");
            for (self.string_table.items, 0..) |str, i| {
                try writer.print(".str{d}: \"{s}\"\n", .{ i, str });
            }
            try writer.writeAll("\n");
        }

        // Print global variables
        if (self.globals.items.len > 0) {
            try writer.writeAll("=== Global Variables ===\n");
            for (self.globals.items) |global| {
                try writer.print("{s}", .{global.name});
                if (global.type_hint) |hint| {
                    try writer.print(" [{s}]", .{hint});
                }
                if (global.init_value) |init_val| {
                    try writer.print(" = {any}", .{init_val});
                }
                try writer.writeAll("\n");
            }
            try writer.writeAll("\n");
        }

        // Print functions
        for (self.functions.items) |func| {
            try writer.print("=== Function: {s} ===\n", .{func.name});
            try writer.print("params={d}, locals={d}, temps={d}\n", .{
                func.param_count,
                func.local_count,
                func.temp_count,
            });
            if (func.return_type) |ret| {
                try writer.print("returns: {s}\n", .{ret});
            }
            try writer.writeAll("\n");

            for (func.blocks.items) |block| {
                try writer.print("  block{d}:\n", .{block.id});
                for (block.instructions.items) |instr| {
                    try writer.print("    {any}\n", .{instr});
                }
                try writer.writeAll("\n");
            }
        }
    }
};
