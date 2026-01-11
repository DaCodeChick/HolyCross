const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("../ir.zig");

/// Context for assembly generation - shared state
pub const GenContext = struct {
    allocator: Allocator,
    output: *std.ArrayList(u8),
    current_layout: ?*const StackLayout,
    current_module: ?*const ir.Module,

    /// Emit assembly code
    pub fn emit(self: *GenContext, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer(self.allocator).print(fmt, args);
    }

    /// Emit assembly comment
    pub fn emitComment(self: *GenContext, comptime fmt: []const u8, args: anytype) !void {
        try self.output.writer(self.allocator).print("    # ", .{});
        try self.output.writer(self.allocator).print(fmt, args);
        try self.output.writer(self.allocator).print("\n", .{});
    }

    /// Get variable offset from stack layout
    pub fn getVarOffset(self: *const GenContext, name: []const u8) i64 {
        if (self.current_layout) |layout| {
            return layout.getVarOffset(name) orelse {
                std.debug.print("Warning: No offset for variable {s}\n", .{name});
                return 8;
            };
        }
        unreachable; // Layout must exist during codegen
    }

    /// Get temporary offset from stack layout
    pub fn getTempOffset(self: *const GenContext, temp_id: u32) i64 {
        if (self.current_layout) |layout| {
            return layout.getTempOffset(temp_id) orelse {
                std.debug.print("Warning: No offset for temp t{d}\n", .{temp_id});
                return 8;
            };
        }
        unreachable; // Layout must exist during codegen
    }

    /// Find string in module's string table
    pub fn findStringId(self: *const GenContext, str: []const u8) ?usize {
        if (self.current_module) |module| {
            for (module.string_table.items, 0..) |s, i| {
                if (std.mem.eql(u8, s, str)) {
                    return i;
                }
            }
        }
        return null;
    }
};

/// Stack layout for a function - tracks offsets for variables and temporaries
pub const StackLayout = struct {
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

/// Common assembly patterns
pub const Patterns = struct {
    /// Emit function prologue
    pub fn emitFunctionPrologue(ctx: *GenContext, func_name: []const u8, stack_size: usize) !void {
        try ctx.emit(".globl {s}\n", .{func_name});
        try ctx.emit(".type {s}, @function\n", .{func_name});
        try ctx.emit("{s}:\n", .{func_name});
        try ctx.emit("    push rbp\n", .{});
        try ctx.emit("    mov rbp, rsp\n", .{});
        if (stack_size > 0) {
            try ctx.emit("    sub rsp, {d}\n", .{stack_size});
        }
    }

    /// Emit function epilogue
    pub fn emitFunctionEpilogue(ctx: *GenContext) !void {
        try ctx.emit("    mov rsp, rbp\n", .{});
        try ctx.emit("    pop rbp\n", .{});
        try ctx.emit("    ret\n", .{});
    }

    /// Emit conditional jump (test rax and jump if condition)
    pub fn emitConditionalJump(ctx: *GenContext, condition: []const u8, label: u32) !void {
        try ctx.emit("    test rax, rax\n", .{});
        try ctx.emit("    {s} .L{d}\n", .{ condition, label });
    }

    /// Load operand into register
    pub fn loadOperand(ctx: *GenContext, operand: ir.Operand, dest_reg: []const u8) !void {
        switch (operand) {
            .none => {},
            .temp => |t| {
                const offset = ctx.getTempOffset(t);
                try ctx.emit("    mov {s}, [rbp-{d}]  # t{d}\n", .{ dest_reg, offset, t });
            },
            .variable => |v| {
                const offset = ctx.getVarOffset(v);
                try ctx.emit("    mov {s}, [rbp-{d}]  # {s}\n", .{ dest_reg, offset, v });
            },
            .constant => |c| switch (c) {
                .int => |i| {
                    try ctx.emit("    mov {s}, {d}\n", .{ dest_reg, i });
                },
                .float => |f| {
                    try ctx.emit("    movq {s}, {d}\n", .{ dest_reg, @as(i64, @bitCast(f)) });
                },
                .bool => |b| {
                    try ctx.emit("    mov {s}, {d}\n", .{ dest_reg, if (b) @as(i64, 1) else @as(i64, 0) });
                },
            },
            .label => {},
            .function => {},
            .string => {},
        }
    }

    /// Store register to operand
    pub fn storeOperand(ctx: *GenContext, operand: ir.Operand, src_reg: []const u8) !void {
        switch (operand) {
            .temp => |t| {
                const offset = ctx.getTempOffset(t);
                try ctx.emit("    mov [rbp-{d}], {s}  # t{d}\n", .{ offset, src_reg, t });
            },
            .variable => |v| {
                const offset = ctx.getVarOffset(v);
                try ctx.emit("    mov [rbp-{d}], {s}  # {s}\n", .{ offset, src_reg, v });
            },
            else => {},
        }
    }
};
