const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../parser/ast.zig");
const ir = @import("ir.zig");

/// IR Builder - converts AST to IR
pub const IRBuilder = struct {
    allocator: Allocator,
    module: ir.Module,
    current_function: ?*ir.Function,
    current_block: ?*ir.BasicBlock,
    temp_counter: u32,
    label_counter: u32,

    pub fn init(allocator: Allocator) !IRBuilder {
        return .{
            .allocator = allocator,
            .module = try ir.Module.init(allocator),
            .current_function = null,
            .current_block = null,
            .temp_counter = 0,
            .label_counter = 0,
        };
    }

    pub fn deinit(self: *IRBuilder) void {
        self.module.deinit();
    }

    /// Generate a new temporary register
    fn newTemp(self: *IRBuilder) u32 {
        const temp = self.temp_counter;
        self.temp_counter += 1;
        return temp;
    }

    /// Generate a new label ID
    fn newLabel(self: *IRBuilder) u32 {
        const label = self.label_counter;
        self.label_counter += 1;
        return label;
    }

    /// Emit an instruction to the current block
    fn emit(self: *IRBuilder, instr: ir.Instruction) !void {
        if (self.current_block) |block| {
            try block.instructions.append(self.allocator, instr);
        } else {
            return error.NoCurrentBlock;
        }
    }

    /// Build IR from AST root
    pub fn buildFromAST(self: *IRBuilder, root: *const ast.Program) !void {
        for (root.decls) |decl| {
            try self.buildDeclaration(decl);
        }
    }

    pub fn buildDeclaration(self: *IRBuilder, decl: ast.Decl) !void {
        switch (decl) {
            .function => |func| try self.buildFunction(func),
            .global_var => {}, // Global variables - TODO later
            .class => {}, // Class declarations - TODO later
            .union_decl => {}, // Union declarations - TODO later
            .import => {}, // Imports - TODO later
            .preprocessor => {}, // Preprocessor - TODO later
        }
    }

    fn buildFunction(self: *IRBuilder, func: @TypeOf(@as(ast.Decl, undefined).function)) !void {
        // Create IR function
        const ir_func = try self.module.createFunction(func.name);
        self.current_function = ir_func;
        self.temp_counter = 0;

        // Set function metadata
        ir_func.param_count = @intCast(func.params.len);
        // TODO: Set return type based on func.return_type

        // Create entry block
        const entry = try ir_func.createBlock();
        self.current_block = entry;

        // Allocate space for parameters
        for (func.params) |param| {
            try self.emit(.{
                .opcode = .param,
                .dest = .{ .variable = param.name },
                .type_hint = self.typeToString(param.type),
            });
        }

        // Build function body
        if (func.body) |body| {
            try self.buildStatement(body);
        }

        // Ensure function ends with return
        const last_block = ir_func.blocks.items[ir_func.blocks.items.len - 1];
        if (last_block.instructions.items.len == 0 or
            (last_block.instructions.items[last_block.instructions.items.len - 1].opcode != .ret and
                last_block.instructions.items[last_block.instructions.items.len - 1].opcode != .ret_val))
        {
            try self.emit(.{ .opcode = .ret });
        }

        // Update function metadata
        ir_func.temp_count = self.temp_counter;

        self.current_function = null;
        self.current_block = null;
    }

    fn buildStatement(self: *IRBuilder, stmt: ast.Stmt) anyerror!void {
        switch (stmt) {
            .expr => |expr_stmt| {
                _ = try self.buildExpression(expr_stmt.expr);
            },
            .return_stmt => |ret| {
                if (ret.expr) |val| {
                    const result = try self.buildExpression(val);
                    try self.emit(.{
                        .opcode = .ret_val,
                        .src1 = result,
                    });
                } else {
                    try self.emit(.{ .opcode = .ret });
                }
            },
            .var_decl => |decl| {
                try self.buildVariableDecl(decl);
            },
            .block => |block| {
                for (block.stmts) |s| {
                    try self.buildStatement(s);
                }
            },
            .if_stmt => |if_stmt| {
                try self.buildIfStatement(if_stmt);
            },
            .while_stmt => |while_stmt| {
                try self.buildWhileStatement(while_stmt);
            },
            .for_stmt => |for_stmt| {
                try self.buildForStatement(for_stmt);
            },
            .switch_stmt => {
                // TODO: Switch statements
            },
            .goto_stmt => {
                // TODO: Goto statements
            },
            .label => {
                // TODO: Label statements
            },
            .break_stmt => {
                // TODO: Break statements
            },
            .do_while => {
                // TODO: Do-while statements
            },
            .try_catch => {
                // TODO: Try statements
            },
            .asm_block => {
                // TODO: Assembly statements
            },
            .empty => {},
        }
    }

    fn buildVariableDecl(self: *IRBuilder, decl: @TypeOf(@as(ast.Stmt, undefined).var_decl)) !void {
        if (self.current_function) |func| {
            func.local_count += 1;
        }

        // Allocate stack space for variable
        try self.emit(.{
            .opcode = .alloc_local,
            .dest = .{ .variable = decl.name },
            .src1 = .{ .constant = .{ .int = 8 } }, // TODO: Get actual size from type
            .type_hint = self.typeToString(decl.type),
        });

        // Initialize if there's an initializer
        if (decl.init) |initializer| {
            const value = try self.buildExpression(initializer);
            try self.emit(.{
                .opcode = .store_var,
                .dest = .{ .variable = decl.name },
                .src1 = value,
            });
        }
    }

    fn buildIfStatement(self: *IRBuilder, if_stmt: @TypeOf(@as(ast.Stmt, undefined).if_stmt)) !void {
        const then_label = self.newLabel();
        const else_label = self.newLabel();
        const end_label = self.newLabel();

        // Evaluate condition
        const cond = try self.buildExpression(if_stmt.condition);

        // Jump to else/end if condition is false (zero)
        if (if_stmt.else_stmt) |_| {
            try self.emit(.{
                .opcode = .jump_if_zero,
                .src1 = cond,
                .dest = .{ .label = else_label },
            });
        } else {
            try self.emit(.{
                .opcode = .jump_if_zero,
                .src1 = cond,
                .dest = .{ .label = end_label },
            });
        }

        // Then branch
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = then_label },
        });
        try self.buildStatement(if_stmt.then_stmt.*);
        try self.emit(.{
            .opcode = .jump,
            .dest = .{ .label = end_label },
        });

        // Else branch (if present)
        if (if_stmt.else_stmt) |else_branch| {
            try self.emit(.{
                .opcode = .label,
                .dest = .{ .label = else_label },
            });
            try self.buildStatement(else_branch.*);
        }

        // End label
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = end_label },
        });
    }

    fn buildWhileStatement(self: *IRBuilder, while_stmt: @TypeOf(@as(ast.Stmt, undefined).while_stmt)) !void {
        const loop_label = self.newLabel();
        const body_label = self.newLabel();
        const end_label = self.newLabel();

        // Loop header
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = loop_label },
        });

        // Evaluate condition
        const cond = try self.buildExpression(while_stmt.condition);

        // Jump to end if condition is false
        try self.emit(.{
            .opcode = .jump_if_zero,
            .src1 = cond,
            .dest = .{ .label = end_label },
        });

        // Body
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = body_label },
        });
        try self.buildStatement(while_stmt.body.*);

        // Jump back to loop header
        try self.emit(.{
            .opcode = .jump,
            .dest = .{ .label = loop_label },
        });

        // End label
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = end_label },
        });
    }

    fn buildForStatement(self: *IRBuilder, for_stmt: @TypeOf(@as(ast.Stmt, undefined).for_stmt)) !void {
        // Initialize
        if (for_stmt.init) |init_stmt| {
            try self.buildStatement(init_stmt.*);
        }

        const loop_label = self.newLabel();
        const body_label = self.newLabel();
        const continue_label = self.newLabel();
        const end_label = self.newLabel();

        // Loop header
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = loop_label },
        });

        // Condition
        if (for_stmt.condition) |cond_expr| {
            const cond = try self.buildExpression(cond_expr);
            try self.emit(.{
                .opcode = .jump_if_zero,
                .src1 = cond,
                .dest = .{ .label = end_label },
            });
        }

        // Body
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = body_label },
        });
        try self.buildStatement(for_stmt.body.*);

        // Continue label (for continue statements)
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = continue_label },
        });

        // Increment
        if (for_stmt.increment) |inc| {
            _ = try self.buildExpression(inc);
        }

        // Jump back to loop header
        try self.emit(.{
            .opcode = .jump,
            .dest = .{ .label = loop_label },
        });

        // End label
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = end_label },
        });
    }

    fn buildExpression(self: *IRBuilder, expr: ast.Expr) anyerror!ir.Operand {
        switch (expr) {
            .integer => |int| {
                return .{ .constant = .{ .int = int.value } };
            },
            .float => |flt| {
                return .{ .constant = .{ .float = flt.value } };
            },
            .string => |str| {
                _ = try self.module.addStringLiteral(str.value);
                // For HolyC print: "text" is actually a print statement
                // We'll emit a print instruction
                try self.emit(.{
                    .opcode = .print,
                    .src1 = .{ .string = str.value },
                });
                return .{ .string = str.value };
            },
            .char => |ch| {
                return .{ .constant = .{ .int = @intCast(ch.value) } };
            },
            .identifier => |ident| {
                const temp = self.newTemp();
                try self.emit(.{
                    .opcode = .load_var,
                    .dest = .{ .temp = temp },
                    .src1 = .{ .variable = ident.name },
                });
                return .{ .temp = temp };
            },
            .binary => |bin| {
                return try self.buildBinaryOp(bin);
            },
            .unary => |un| {
                return try self.buildUnaryOp(un);
            },
            .call => |call| {
                return try self.buildCall(call);
            },
            .member, .arrow => {
                // TODO: Member access
                return .{ .temp = self.newTemp() };
            },
            .subscript => {
                // TODO: Array subscript
                return .{ .temp = self.newTemp() };
            },
            .cast => |cast| {
                // For now, just evaluate the expression
                // TODO: Proper type casting
                return try self.buildExpression(cast.expr.*);
            },
            .sizeof_expr, .sizeof_type, .offset => {
                // TODO: Sizeof and offset
                return .{ .constant = .{ .int = 8 } };
            },
        }
    }

    fn buildBinaryOp(self: *IRBuilder, bin: @TypeOf(@as(ast.Expr, undefined).binary)) !ir.Operand {
        // Handle assignment operators specially
        if (bin.op == .assign) {
            const value = try self.buildExpression(bin.right.*);
            const var_name = switch (bin.left.*) {
                .identifier => |ident| ident.name,
                else => "unknown",
            };
            try self.emit(.{
                .opcode = .store_var,
                .dest = .{ .variable = var_name },
                .src1 = value,
            });
            return value;
        }

        const left = try self.buildExpression(bin.left.*);
        const right = try self.buildExpression(bin.right.*);
        const temp = self.newTemp();

        const opcode: ir.Opcode = switch (bin.op) {
            .add, .add_assign => .add,
            .subtract, .sub_assign => .sub,
            .multiply, .mul_assign => .mul,
            .divide, .div_assign => .div,
            .modulo, .mod_assign => .mod,
            .bitwise_and, .and_assign => .bit_and,
            .bitwise_or, .or_assign => .bit_or,
            .bitwise_xor, .xor_assign => .bit_xor,
            .shift_left, .shl_assign => .shl,
            .shift_right, .shr_assign => .shr,
            .logical_and => .log_and,
            .logical_or => .log_or,
            .logical_xor => .log_xor,
            .equal => .cmp_eq,
            .not_equal => .cmp_ne,
            .less => .cmp_lt,
            .less_equal => .cmp_le,
            .greater => .cmp_gt,
            .greater_equal => .cmp_ge,
            else => .add, // TODO: Handle other operators
        };

        try self.emit(.{
            .opcode = opcode,
            .dest = .{ .temp = temp },
            .src1 = left,
            .src2 = right,
        });

        return .{ .temp = temp };
    }

    fn buildUnaryOp(self: *IRBuilder, un: @TypeOf(@as(ast.Expr, undefined).unary)) !ir.Operand {
        const operand = try self.buildExpression(un.operand.*);
        const temp = self.newTemp();

        const opcode: ir.Opcode = switch (un.op) {
            .negate => .neg,
            .bitwise_not => .bit_not,
            .logical_not => .log_not,
            else => .move, // TODO: Handle other unary operators
        };

        try self.emit(.{
            .opcode = opcode,
            .dest = .{ .temp = temp },
            .src1 = operand,
        });

        return .{ .temp = temp };
    }

    fn buildCall(self: *IRBuilder, call: @TypeOf(@as(ast.Expr, undefined).call)) !ir.Operand {
        // Build arguments
        // TODO: Pass arguments properly
        for (call.args) |arg| {
            _ = try self.buildExpression(arg);
        }

        // Get function name
        const func_name = switch (call.callee.*) {
            .identifier => |ident| ident.name,
            else => "unknown",
        };

        const temp = self.newTemp();
        try self.emit(.{
            .opcode = .call,
            .src1 = .{ .function = func_name },
            .dest = .{ .temp = temp },
        });

        return .{ .temp = temp };
    }

    fn typeToString(self: *IRBuilder, typ: ast.Type) ?[]const u8 {
        _ = self;
        return switch (typ) {
            .i0 => "I0",
            .i8 => "I8",
            .i16 => "I16",
            .i32 => "I32",
            .i64 => "I64",
            .u0 => "U0",
            .u8 => "U8",
            .u16 => "U16",
            .u32 => "U32",
            .u64 => "U64",
            .f64 => "F64",
            else => null,
        };
    }

    pub fn finish(self: *IRBuilder) !ir.Module {
        const module = self.module;
        self.module = try ir.Module.init(self.allocator);
        return module;
    }
};
