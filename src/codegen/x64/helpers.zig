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
        // Zig 0.16.0: Use allocPrint + appendSlice instead of ArrayList.print
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.output.appendSlice(self.allocator, formatted);
    }

    /// Emit assembly comment
    pub fn emitComment(self: *GenContext, comptime fmt: []const u8, args: anytype) !void {
        try self.output.appendSlice(self.allocator, "\t//");
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.output.appendSlice(self.allocator, formatted);
        try self.output.append(self.allocator, '\n');
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

    /// Check if a variable is global
    pub fn isGlobalVar(self: *const GenContext, name: []const u8) bool {
        if (self.current_module) |module| {
            for (module.globals.items) |global| {
                if (std.mem.eql(u8, global.name, name)) {
                    return true;
                }
            }
        }
        return false;
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
        // TempleOS syntax: _NAME:: for C-callable functions
        try ctx.emit("_{s}::\n", .{func_name});
        try ctx.emit("\tPUSH\tRBP\n", .{});
        try ctx.emit("\tMOV\tRBP,RSP\n", .{});
        if (stack_size > 0) {
            try ctx.emit("\tSUB\tRSP,{d}\n", .{stack_size});
        }
    }

    /// Emit function epilogue
    pub fn emitFunctionEpilogue(ctx: *GenContext) !void {
        try ctx.emit("\tMOV\tRSP,RBP\n", .{});
        try ctx.emit("\tPOP\tRBP\n", .{});
        try ctx.emit("\tRET\n", .{});
    }

    /// Emit conditional jump (test rax and jump if condition)
    pub fn emitConditionalJump(ctx: *GenContext, condition: []const u8, label: u32) !void {
        try ctx.emit("\tTEST\tRAX,RAX\n", .{});
        try ctx.emit("\t{s}\t@@{d:0>2}\n", .{ condition, label });
    }

    /// Load operand into register
    pub fn loadOperand(ctx: *GenContext, operand: ir.Operand, dest_reg: []const u8) !void {
        switch (operand) {
            .none => {},
            .temp => |t| {
                const offset = ctx.getTempOffset(t);
                try ctx.emit("\tMOV\t{s},[RBP-{d}]\t//t{d}\n", .{ dest_reg, offset, t });
            },
            .variable => |v| {
                const offset = ctx.getVarOffset(v);
                try ctx.emit("\tMOV\t{s},[RBP-{d}]\t//{s}\n", .{ dest_reg, offset, v });
            },
            .constant => |c| switch (c) {
                .int => |i| {
                    try ctx.emit("\tMOV\t{s},{d}\n", .{ dest_reg, i });
                },
                .float => |f| {
                    try ctx.emit("\tMOV\t{s},{d}\n", .{ dest_reg, @as(i64, @bitCast(f)) });
                },
                .bool => |b| {
                    try ctx.emit("\tMOV\t{s},{d}\n", .{ dest_reg, if (b) @as(i64, 1) else @as(i64, 0) });
                },
            },
            else => {},
        }
    }

    /// Store register to operand
    pub fn storeOperand(ctx: *GenContext, operand: ir.Operand, src_reg: []const u8) !void {
        switch (operand) {
            .none => {},
            .temp => |t| {
                const offset = ctx.getTempOffset(t);
                try ctx.emit("\tMOV\t[RBP-{d}],{s}\t//t{d}\n", .{ offset, src_reg, t });
            },
            .variable => |v| {
                const offset = ctx.getVarOffset(v);
                try ctx.emit("\tMOV\t[RBP-{d}],{s}\t//{s}\n", .{ offset, src_reg, v });
            },
            else => {},
        }
    }

    /// Load float operand to x87 FPU stack (ST0)
    pub fn loadFloatToST0(ctx: *GenContext, operand: ir.Operand) !void {
        switch (operand) {
            .temp => |t| {
                const offset = ctx.getTempOffset(t);
                try ctx.emit("\tFLD\tU64 [RBP-{d}]\t//t{d}\n", .{ offset, t });
            },
            .variable => |v| {
                const offset = ctx.getVarOffset(v);
                try ctx.emit("\tFLD\tU64 [RBP-{d}]\t//{s}\n", .{ offset, v });
            },
            .constant => |c| switch (c) {
                .float => |f| {
                    // For float constants, we need to emit them as 64-bit bit pattern
                    const bits: u64 = @bitCast(f);
                    try ctx.emit("\tMOV\tRAX,0x{X}\n", .{bits});
                    try ctx.emit("\tPUSH\tRAX\n", .{});
                    try ctx.emit("\tFLD\tU64 [RSP]\n", .{});
                    try ctx.emit("\tADD\tRSP,8\n", .{});
                },
                else => {},
            },
            else => {},
        }
    }

    /// Store float from x87 FPU stack (ST0) to operand and pop
    pub fn storeFloatFromST0(ctx: *GenContext, operand: ir.Operand) !void {
        switch (operand) {
            .temp => |t| {
                const offset = ctx.getTempOffset(t);
                try ctx.emit("\tFSTP\tU64 [RBP-{d}]\t//t{d}\n", .{ offset, t });
            },
            .variable => |v| {
                const offset = ctx.getVarOffset(v);
                try ctx.emit("\tFSTP\tU64 [RBP-{d}]\t//{s}\n", .{ offset, v });
            },
            else => {},
        }
    }
};
