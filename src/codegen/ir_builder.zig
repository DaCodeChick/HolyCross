//! IR Builder - converts AST to Intermediate Representation
//!
//! This module performs the first stage of code generation by converting
//! the typed AST into a low-level IR that is easier to translate to x64.
//!
//! Structure (with approximate line numbers):
//! - IRBuilder Init/Deinit (lines 7-32): Main builder struct and lifecycle
//! - Helper Functions (lines 34-55): Temp/label generation, instruction emission
//! - Declaration Building (lines 57-117): Top-level declarations and functions
//! - Statement Building (lines 119-407): All statement types (if, while, for, etc.)
//! - Expression Building (lines 408-726): All expression types and operators
//! - Type Conversion (lines 727-750): Convert AST types to string hints
//!
//! Key Features:
//! - Basic block generation for control flow
//! - SSA-style temporary registers
//! - Loop label stack for break statements
//! - Placeholder TODOs for future features (switch, goto, classes, etc.)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("../parser/ast.zig");
const ir = @import("ir.zig");
const type_checker_module = @import("../semantic/type_checker.zig");
const type_layout_module = @import("../semantic/type_layout.zig");

const TypeChecker = type_checker_module.TypeChecker;
const TypeLayout = type_layout_module.TypeLayout;

/// IR Builder - converts AST to IR
pub const IRBuilder = struct {
    allocator: Allocator,
    module: ir.Module,
    current_function: ?*ir.Function,
    current_block: ?*ir.BasicBlock,
    temp_counter: u32,
    label_counter: u32,
    break_label_stack: std.ArrayList(u32), // Track break labels for nested loops
    label_map: std.StringHashMap(u32), // Map label names to label IDs (per function)
    type_checker: ?*TypeChecker, // Optional type checker for type inference
    type_layouts: ?*const std.StringHashMap(TypeLayout), // Optional type layout map
    allocated_type_hints: std.ArrayList([]const u8), // Track allocated type hint strings for cleanup

    pub fn init(allocator: Allocator, type_checker: ?*TypeChecker, type_layouts: ?*const std.StringHashMap(TypeLayout)) !IRBuilder {
        const empty_labels = try allocator.alloc(u32, 0);
        const empty_hints = try allocator.alloc([]const u8, 0);
        return .{
            .allocator = allocator,
            .module = try ir.Module.init(allocator),
            .current_function = null,
            .current_block = null,
            .temp_counter = 0,
            .label_counter = 0,
            .break_label_stack = std.ArrayList(u32).fromOwnedSlice(empty_labels),
            .label_map = std.StringHashMap(u32).init(allocator),
            .type_checker = type_checker,
            .type_layouts = type_layouts,
            .allocated_type_hints = std.ArrayList([]const u8).fromOwnedSlice(empty_hints),
        };
    }

    pub fn deinit(self: *IRBuilder) void {
        // Free allocated type hint strings
        for (self.allocated_type_hints.items) |hint| {
            self.allocator.free(hint);
        }
        self.allocated_type_hints.deinit(self.allocator);
        
        self.module.deinit();
        self.break_label_stack.deinit(self.allocator);
        self.label_map.deinit();
    }

    // ========================================================================
    // Helper Functions
    // ========================================================================

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

    /// Get or create a label ID for a named label (used for goto/label)
    fn getOrCreateLabel(self: *IRBuilder, name: []const u8) !u32 {
        if (self.label_map.get(name)) |existing_id| {
            return existing_id;
        }
        const new_id = self.newLabel();
        try self.label_map.put(name, new_id);
        return new_id;
    }

    /// Emit an instruction to the current block
    fn emit(self: *IRBuilder, instr: ir.Instruction) !void {
        if (self.current_block) |block| {
            try block.instructions.append(self.allocator, instr);
        } else {
            return error.NoCurrentBlock;
        }
    }

    // ========================================================================
    // Declaration Building
    // ========================================================================

    /// Build IR from AST root
    pub fn buildFromAST(self: *IRBuilder, root: *const ast.Program) !void {
        // Check if there's a HolyC Main function or a C main function
        var has_main = false;
        var has_c_main = false;
        for (root.decls) |decl| {
            if (decl == .function) {
                if (std.mem.eql(u8, decl.function.name, "Main")) {
                    has_main = true;
                } else if (std.mem.eql(u8, decl.function.name, "main")) {
                    has_c_main = true;
                }
            }
        }

        // First, process all declarations (including Main/main if they exist)
        for (root.decls) |decl| {
            try self.buildDeclaration(decl);
        }

        // Create C's main() function that:
        // 1. Executes top-level statements (if any)
        // 2. Calls HolyC Main() function (if it exists)
        // BUT: Only if user didn't define their own main() function
        if (!has_c_main) {
            try self.buildCMainFunction(root.top_level_stmts, has_main);
        }
    }

    pub fn buildDeclaration(self: *IRBuilder, decl: ast.Decl) !void {
        switch (decl) {
            .function => |func| try self.buildFunction(func),
            .global_var => |gvar| try self.buildGlobalVariable(gvar),
            .class => {}, // Class declarations - TODO later
            .union_decl => {}, // Union declarations - TODO later
            .import => {}, // Imports - TODO later
            .preprocessor => {}, // Preprocessor - TODO later
        }
    }

    fn buildFunction(self: *IRBuilder, func: @TypeOf(@as(ast.Decl, undefined).function)) !void {
        // Skip extern functions without bodies (forward declarations)
        if (func.attributes.is_extern and func.body == null) {
            return;
        }

        // Create IR function
        const ir_func = try self.module.createFunction(func.name);
        self.current_function = ir_func;
        self.temp_counter = 0;

        // Clear label map for new function
        self.label_map.clearRetainingCapacity();

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

    /// Build C's main() function that executes top-level statements and calls HolyC Main()
    fn buildCMainFunction(self: *IRBuilder, top_level_stmts: []const ast.Stmt, has_holys_main: bool) !void {
        // Create IR function for C's main entry point
        const ir_func = try self.module.createFunction("main");
        self.current_function = ir_func;
        self.temp_counter = 0;

        // Clear label map for new function
        self.label_map.clearRetainingCapacity();

        // Set function metadata (no parameters for now - TODO: handle argc/argv)
        ir_func.param_count = 0;

        // Create entry block
        const entry = try ir_func.createBlock();
        self.current_block = entry;

        // First, execute all top-level statements
        for (top_level_stmts) |stmt| {
            try self.buildStatement(stmt);
        }

        // Then, if there's a HolyC Main function, call it
        if (has_holys_main) {
            // Create call to Main() with no arguments
            const temp = self.newTemp();
            const empty_args = try self.allocator.alloc(ir.Operand, 0);

            try self.emit(.{
                .opcode = .call,
                .dest = .{ .temp = temp },
                .src1 = .{ .function = "Main" },
                .args = empty_args,
            });
        }

        // Return 0 from main
        try self.emit(.{
            .opcode = .ret_val,
            .src1 = .{ .constant = .{ .int = 0 } },
        });

        // Update function metadata
        ir_func.temp_count = self.temp_counter;

        self.current_function = null;
        self.current_block = null;
    }

    fn buildGlobalVariable(self: *IRBuilder, gvar: @TypeOf(@as(ast.Decl, undefined).global_var)) !void {
        // Evaluate initializer if present
        var init_value: ?ir.Operand = null;
        if (gvar.init) |init_expr| {
            // For globals, we can only handle constant initializers
            init_value = switch (init_expr) {
                .integer => |int| .{ .constant = .{ .int = int.value } },
                .float => |flt| .{ .constant = .{ .float = flt.value } },
                .char => |ch| .{ .constant = .{ .int = @intCast(ch.value) } },
                else => null, // Non-constant initializers need runtime code
            };
        }

        try self.module.addGlobal(gvar.name, self.typeToString(gvar.type), init_value);
    }

    // ========================================================================
    // Statement Building
    // ========================================================================

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
            .switch_stmt => |switch_stmt| {
                try self.buildSwitchStatement(switch_stmt);
            },
            .goto_stmt => |goto_stmt| {
                // Get or create label ID for this label name
                const label_id = try self.getOrCreateLabel(goto_stmt.label);
                try self.emit(.{
                    .opcode = .jump,
                    .dest = .{ .label = label_id },
                });
            },
            .label => |label_stmt| {
                // Get or create label ID for this label name
                const label_id = try self.getOrCreateLabel(label_stmt.name);
                try self.emit(.{
                    .opcode = .label,
                    .dest = .{ .label = label_id },
                });
            },
            .break_stmt => {
                // Get the current loop's end label from the stack
                if (self.break_label_stack.items.len > 0) {
                    const break_label = self.break_label_stack.items[self.break_label_stack.items.len - 1];
                    try self.emit(.{
                        .opcode = .jump,
                        .dest = .{ .label = break_label },
                    });
                } else {
                    return error.BreakOutsideLoop;
                }
            },
            .do_while => |do_while_stmt| {
                try self.buildDoWhileStatement(do_while_stmt);
            },
            .try_catch => |try_catch| {
                // Try-catch: for now, just execute the try block
                // TODO: Proper exception handling would require runtime support
                try self.buildStatement(try_catch.try_block.*);
                // Ignore catch block for now
            },
            .asm_block => |asm_block| {
                // Emit inline assembly instruction
                try self.emit(.{
                    .opcode = .inline_asm,
                    .src1 = .{ .string = asm_block.code },
                });
            },
            .empty => {},
        }
    }

    fn buildVariableDecl(self: *IRBuilder, decl: @TypeOf(@as(ast.Stmt, undefined).var_decl)) !void {
        if (self.current_function) |func| {
            func.local_count += 1;
        }

        // Allocate stack space for variable
        const type_size = self.calculateTypeSize(decl.type);
        try self.emit(.{
            .opcode = .alloc_local,
            .dest = .{ .variable = decl.name },
            .src1 = .{ .constant = .{ .int = type_size } },
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

        // Push end_label to break stack for break statements
        try self.break_label_stack.append(self.allocator, end_label);
        defer _ = self.break_label_stack.pop();

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

        // Push end_label to break stack for break statements
        try self.break_label_stack.append(self.allocator, end_label);
        defer _ = self.break_label_stack.pop();

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

    fn buildDoWhileStatement(self: *IRBuilder, do_while_stmt: @TypeOf(@as(ast.Stmt, undefined).do_while)) !void {
        const body_label = self.newLabel();
        const condition_label = self.newLabel();
        const end_label = self.newLabel();

        // Push end_label to break stack for break statements
        try self.break_label_stack.append(self.allocator, end_label);
        defer _ = self.break_label_stack.pop();

        // Body label - do-while executes body at least once
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = body_label },
        });

        // Execute body
        try self.buildStatement(do_while_stmt.body.*);

        // Condition label
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = condition_label },
        });

        // Evaluate condition
        const cond = try self.buildExpression(do_while_stmt.condition);

        // Jump back to body if condition is true (non-zero)
        try self.emit(.{
            .opcode = .jump_if_not_zero,
            .src1 = cond,
            .dest = .{ .label = body_label },
        });

        // End label
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = end_label },
        });
    }

    fn buildSwitchStatement(self: *IRBuilder, switch_stmt: @TypeOf(@as(ast.Stmt, undefined).switch_stmt)) !void {
        const end_label = self.newLabel();

        // Push end_label to break stack for break statements
        try self.break_label_stack.append(self.allocator, end_label);
        defer _ = self.break_label_stack.pop();

        // Evaluate switch expression once
        const switch_value = try self.buildExpression(switch_stmt.expr);

        // Create labels for each case
        const case_labels = try self.allocator.alloc(u32, switch_stmt.cases.len);
        defer self.allocator.free(case_labels);

        var default_label: ?u32 = null;

        for (switch_stmt.cases, 0..) |case, i| {
            case_labels[i] = self.newLabel();
            if (case.value == null) {
                default_label = case_labels[i];
            }
        }

        // Generate comparison and jumps for each case
        for (switch_stmt.cases, 0..) |case, i| {
            if (case.value) |case_value| {
                // Evaluate case value
                const case_val = try self.buildExpression(case_value);

                // Compare: switch_value == case_value
                const cmp_result = self.newTemp();
                try self.emit(.{
                    .opcode = .cmp_eq,
                    .dest = .{ .temp = cmp_result },
                    .src1 = switch_value,
                    .src2 = case_val,
                });

                // Jump to case label if equal
                try self.emit(.{
                    .opcode = .jump_if_not_zero,
                    .src1 = .{ .temp = cmp_result },
                    .dest = .{ .label = case_labels[i] },
                });
            }
        }

        // If no case matched, jump to default or end
        if (default_label) |def_label| {
            try self.emit(.{
                .opcode = .jump,
                .dest = .{ .label = def_label },
            });
        } else {
            try self.emit(.{
                .opcode = .jump,
                .dest = .{ .label = end_label },
            });
        }

        // Generate code for each case
        for (switch_stmt.cases, 0..) |case, i| {
            try self.emit(.{
                .opcode = .label,
                .dest = .{ .label = case_labels[i] },
            });

            // Execute case statements
            for (case.stmts) |stmt| {
                try self.buildStatement(stmt);
            }

            // Note: HolyC has implicit fallthrough like C
            // Break statements will jump to end_label via break_label_stack
        }

        // End label
        try self.emit(.{
            .opcode = .label,
            .dest = .{ .label = end_label },
        });
    }

    // ========================================================================
    // Expression Building
    // ========================================================================

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
                return try self.buildMemberAccess(expr);
            },
            .subscript => |sub| {
                return try self.buildSubscript(sub);
            },
            .cast => |cast| {
                // For now, just evaluate the expression
                // TODO: Proper type casting
                return try self.buildExpression(cast.expr.*);
            },
            .sizeof_expr, .sizeof_type, .offset => {
                return try self.buildSizeofOrOffset(expr);
            },
        }
    }

    fn buildBinaryOp(self: *IRBuilder, bin: @TypeOf(@as(ast.Expr, undefined).binary)) !ir.Operand {
        // Handle assignment operators specially
        if (bin.op == .assign) {
            const value = try self.buildExpression(bin.right.*);

            // Check what we're assigning to
            switch (bin.left.*) {
                .identifier => |ident| {
                    // Normal variable assignment: x = value
                    try self.emit(.{
                        .opcode = .store_var,
                        .dest = .{ .variable = ident.name },
                        .src1 = value,
                    });
                },
                .unary => |un| {
                    // Pointer dereference assignment: *ptr = value
                    if (un.op == .dereference) {
                        const ptr = try self.buildExpression(un.operand.*);
                        try self.emit(.{
                            .opcode = .store_ptr,
                            .dest = ptr,
                            .src1 = value,
                        });
                    } else {
                        return error.InvalidAssignmentTarget;
                    }
                },
                .subscript => |sub| {
                    // Array subscript assignment: arr[i] = value
                    // Calculate the address and store to it

                    // Get the base address of the array
                    const base_addr = switch (sub.array.*) {
                        .identifier => |ident| blk: {
                            const temp = self.newTemp();
                            try self.emit(.{
                                .opcode = .load_addr,
                                .dest = .{ .temp = temp },
                                .src1 = .{ .variable = ident.name },
                            });
                            break :blk ir.Operand{ .temp = temp };
                        },
                        else => try self.buildExpression(sub.array.*),
                    };

                    // Evaluate index
                    const index = try self.buildExpression(sub.index.*);

                    // Calculate offset: index * 8 (assuming 8-byte elements)
                    const element_size = self.newTemp();
                    try self.emit(.{
                        .opcode = .load_const,
                        .dest = .{ .temp = element_size },
                        .src1 = .{ .constant = .{ .int = 8 } },
                    });

                    const offset = self.newTemp();
                    try self.emit(.{
                        .opcode = .mul,
                        .dest = .{ .temp = offset },
                        .src1 = index,
                        .src2 = .{ .temp = element_size },
                    });

                    // Calculate final address: base + offset
                    const addr = self.newTemp();
                    try self.emit(.{
                        .opcode = .add,
                        .dest = .{ .temp = addr },
                        .src1 = base_addr,
                        .src2 = .{ .temp = offset },
                    });

                    // Store value to address
                    try self.emit(.{
                        .opcode = .store_ptr,
                        .dest = .{ .temp = addr },
                        .src1 = value,
                    });
                },
                .member => |mem| {
                    // Member access assignment: obj.member = value
                    // Calculate the address of the member and store to it

                    // Get base address of the object
                    const base_addr = switch (mem.object.*) {
                        .identifier => |ident| blk: {
                            const temp = self.newTemp();
                            try self.emit(.{
                                .opcode = .load_addr,
                                .dest = .{ .temp = temp },
                                .src1 = .{ .variable = ident.name },
                            });
                            break :blk ir.Operand{ .temp = temp };
                        },
                        else => try self.buildExpression(mem.object.*),
                    };

                    // Get member offset
                    const member_offset = blk: {
                        // Try to infer the object's type using type checker
                        if (self.type_checker) |tc| {
                            const obj_type = tc.inferExprType(mem.object.*) catch {
                                break :blk self.calculateMemberOffsetFallback(mem.member);
                            };

                            // Get type name for layout lookup
                            const type_name = switch (obj_type) {
                                .named => |name| name,
                                .pointer => |ptr| switch (ptr.*) {
                                    .named => |name| name,
                                    else => {
                                        break :blk self.calculateMemberOffsetFallback(mem.member);
                                    },
                                },
                                else => {
                                    break :blk self.calculateMemberOffsetFallback(mem.member);
                                },
                            };

                            // Look up type layout
                            if (self.type_layouts) |layouts| {
                                if (layouts.get(type_name)) |layout| {
                                    if (layout.getMemberOffset(mem.member)) |offset| {
                                        break :blk @as(i64, @intCast(offset));
                                    }
                                }
                            }
                        }

                        // Fallback to hash-based offset
                        break :blk self.calculateMemberOffsetFallback(mem.member);
                    };

                    // Calculate address: base + offset
                    const offset_temp = self.newTemp();
                    try self.emit(.{
                        .opcode = .load_const,
                        .dest = .{ .temp = offset_temp },
                        .src1 = .{ .constant = .{ .int = member_offset } },
                    });

                    const member_addr = self.newTemp();
                    try self.emit(.{
                        .opcode = .add,
                        .dest = .{ .temp = member_addr },
                        .src1 = base_addr,
                        .src2 = .{ .temp = offset_temp },
                    });

                    // Store value to member address
                    try self.emit(.{
                        .opcode = .store_ptr,
                        .dest = .{ .temp = member_addr },
                        .src1 = value,
                    });
                },
                else => {
                    return error.InvalidAssignmentTarget;
                },
            }
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
        const temp = self.newTemp();

        // Handle address-of specially - we need the variable name, not its value
        if (un.op == .address_of) {
            const var_name = switch (un.operand.*) {
                .identifier => |ident| ident.name,
                else => return error.InvalidAddressOfOperand,
            };
            try self.emit(.{
                .opcode = .load_addr,
                .dest = .{ .temp = temp },
                .src1 = .{ .variable = var_name },
            });
            return .{ .temp = temp };
        }

        // Handle dereference specially - load from pointer
        if (un.op == .dereference) {
            const ptr = try self.buildExpression(un.operand.*);
            try self.emit(.{
                .opcode = .load_ptr,
                .dest = .{ .temp = temp },
                .src1 = ptr,
            });
            return .{ .temp = temp };
        }

        // Handle increment/decrement operators
        // These modify the operand and have different semantics for pre/post
        switch (un.op) {
            .pre_increment, .pre_decrement, .post_increment, .post_decrement => {
                return try self.buildIncrementDecrement(un);
            },
            else => {},
        }

        // For other unary operators, evaluate operand first
        const operand = try self.buildExpression(un.operand.*);

        const opcode: ir.Opcode = switch (un.op) {
            .negate => .neg,
            .bitwise_not => .bit_not,
            .logical_not => .log_not,
            .plus => .move, // Unary plus is just a no-op
            else => return error.UnhandledUnaryOperator,
        };

        try self.emit(.{
            .opcode = opcode,
            .dest = .{ .temp = temp },
            .src1 = operand,
        });

        return .{ .temp = temp };
    }

    fn buildIncrementDecrement(self: *IRBuilder, un: @TypeOf(@as(ast.Expr, undefined).unary)) !ir.Operand {
        // Get the variable name
        const var_name = switch (un.operand.*) {
            .identifier => |ident| ident.name,
            else => return error.InvalidIncrementDecrementTarget,
        };

        // Load current value
        const current = self.newTemp();
        try self.emit(.{
            .opcode = .load_var,
            .dest = .{ .temp = current },
            .src1 = .{ .variable = var_name },
        });

        // Create constant 1
        const one = self.newTemp();
        try self.emit(.{
            .opcode = .load_const,
            .dest = .{ .temp = one },
            .src1 = .{ .constant = .{ .int = 1 } },
        });

        // Calculate new value
        const new_value = self.newTemp();
        const opcode: ir.Opcode = switch (un.op) {
            .pre_increment, .post_increment => .add,
            .pre_decrement, .post_decrement => .sub,
            else => unreachable,
        };

        try self.emit(.{
            .opcode = opcode,
            .dest = .{ .temp = new_value },
            .src1 = .{ .temp = current },
            .src2 = .{ .temp = one },
        });

        // Store new value back
        try self.emit(.{
            .opcode = .store_var,
            .dest = .{ .variable = var_name },
            .src1 = .{ .temp = new_value },
        });

        // Return value depends on pre vs post
        return switch (un.op) {
            .pre_increment, .pre_decrement => .{ .temp = new_value }, // Return new value
            .post_increment, .post_decrement => .{ .temp = current }, // Return old value
            else => unreachable,
        };
    }

    fn buildCall(self: *IRBuilder, call: @TypeOf(@as(ast.Expr, undefined).call)) !ir.Operand {
        // Build argument expressions and collect operands
        const initial_args = try self.allocator.alloc(ir.Operand, 0);
        var arg_operands = std.ArrayList(ir.Operand).fromOwnedSlice(initial_args);
        defer arg_operands.deinit(self.allocator);

        for (call.args) |arg| {
            const arg_operand = try self.buildExpression(arg);
            try arg_operands.append(self.allocator, arg_operand);
        }

        // Get function name
        const func_name = switch (call.callee.*) {
            .identifier => |ident| ident.name,
            else => "unknown",
        };

        const temp = self.newTemp();

        // Create owned copy of arguments for the instruction
        const owned_args = try self.allocator.dupe(ir.Operand, arg_operands.items);

        try self.emit(.{
            .opcode = .call,
            .src1 = .{ .function = func_name },
            .dest = .{ .temp = temp },
            .args = owned_args,
        });

        return .{ .temp = temp };
    }

    fn buildSubscript(self: *IRBuilder, sub: @TypeOf(@as(ast.Expr, undefined).subscript)) !ir.Operand {
        // Calculate array address
        // arr[i] = *(arr + i * element_size)

        // Get the base address of the array
        const base_addr = switch (sub.array.*) {
            .identifier => |ident| blk: {
                const temp = self.newTemp();
                try self.emit(.{
                    .opcode = .load_addr,
                    .dest = .{ .temp = temp },
                    .src1 = .{ .variable = ident.name },
                });
                break :blk ir.Operand{ .temp = temp };
            },
            else => try self.buildExpression(sub.array.*),
        };

        // Evaluate index
        const index = try self.buildExpression(sub.index.*);

        // Calculate offset: index * 8 (assuming 8-byte elements for now)
        const element_size = self.newTemp();
        try self.emit(.{
            .opcode = .load_const,
            .dest = .{ .temp = element_size },
            .src1 = .{ .constant = .{ .int = 8 } },
        });

        const offset = self.newTemp();
        try self.emit(.{
            .opcode = .mul,
            .dest = .{ .temp = offset },
            .src1 = index,
            .src2 = .{ .temp = element_size },
        });

        // Calculate final address: base + offset
        const addr = self.newTemp();
        try self.emit(.{
            .opcode = .add,
            .dest = .{ .temp = addr },
            .src1 = base_addr,
            .src2 = .{ .temp = offset },
        });

        // Load value from address
        const result = self.newTemp();
        try self.emit(.{
            .opcode = .load_ptr,
            .dest = .{ .temp = result },
            .src1 = .{ .temp = addr },
        });

        return .{ .temp = result };
    }

    fn buildMemberAccess(self: *IRBuilder, expr: ast.Expr) !ir.Operand {
        // Handle both . (member) and -> (arrow) access
        // For arrow: ptr->member is equivalent to (*ptr).member

        const object_expr = switch (expr) {
            .member => |m| m.object,
            .arrow => |a| a.object,
            else => unreachable,
        };

        const member_name = switch (expr) {
            .member => |m| m.member,
            .arrow => |a| a.member,
            else => unreachable,
        };

        const is_arrow = switch (expr) {
            .arrow => true,
            else => false,
        };

        // Get base address of the object
        var base_addr: ir.Operand = undefined;

        if (is_arrow) {
            // For arrow: object is already a pointer, just evaluate it
            base_addr = try self.buildExpression(object_expr.*);
        } else {
            // For member: need to get address of the object
            switch (object_expr.*) {
                .identifier => |ident| {
                    const temp = self.newTemp();
                    try self.emit(.{
                        .opcode = .load_addr,
                        .dest = .{ .temp = temp },
                        .src1 = .{ .variable = ident.name },
                    });
                    base_addr = .{ .temp = temp };
                },
                else => {
                    // For complex expressions, evaluate and treat as pointer
                    base_addr = try self.buildExpression(object_expr.*);
                },
            }
        }

        // Get actual member offset from type information
        const member_offset = blk: {
            // Try to infer the object's type using type checker
            if (self.type_checker) |tc| {
                const obj_type = tc.inferExprType(object_expr.*) catch {
                    // If type inference fails, use hash-based fallback
                    break :blk self.calculateMemberOffsetFallback(member_name);
                };

                // Get type name for layout lookup
                const type_name = switch (obj_type) {
                    .named => |name| name,
                    .pointer => |ptr| switch (ptr.*) {
                        .named => |name| name,
                        else => {
                            break :blk self.calculateMemberOffsetFallback(member_name);
                        },
                    },
                    else => {
                        break :blk self.calculateMemberOffsetFallback(member_name);
                    },
                };

                // Look up type layout
                if (self.type_layouts) |layouts| {
                    if (layouts.get(type_name)) |layout| {
                        if (layout.getMemberOffset(member_name)) |offset| {
                            break :blk @as(i64, @intCast(offset));
                        }
                    }
                }
            }

            // Fallback to hash-based offset
            break :blk self.calculateMemberOffsetFallback(member_name);
        };

        // Calculate address: base + offset
        const offset_temp = self.newTemp();
        try self.emit(.{
            .opcode = .load_const,
            .dest = .{ .temp = offset_temp },
            .src1 = .{ .constant = .{ .int = member_offset } },
        });

        const member_addr = self.newTemp();
        try self.emit(.{
            .opcode = .add,
            .dest = .{ .temp = member_addr },
            .src1 = base_addr,
            .src2 = .{ .temp = offset_temp },
        });

        // Load value from member address
        const result = self.newTemp();
        try self.emit(.{
            .opcode = .load_ptr,
            .dest = .{ .temp = result },
            .src1 = .{ .temp = member_addr },
        });

        return .{ .temp = result };
    }

    /// Calculate member offset using hash (fallback when layout is unavailable)
    fn calculateMemberOffsetFallback(self: *IRBuilder, member_name: []const u8) i64 {
        _ = self;
        // Simple hash-based offset for fallback
        var hash: u32 = 0;
        for (member_name) |c| {
            hash = hash *% 31 +% c;
        }
        // Use modulo to keep offsets reasonable (0, 8, 16, 24...)
        return @as(i64, (hash % 8)) * 8;
    }

    fn buildSizeofOrOffset(self: *IRBuilder, expr: ast.Expr) !ir.Operand {
        const size = switch (expr) {
            .sizeof_expr => |s| blk: {
                // Calculate size of the expression's type
                if (self.type_checker) |tc| {
                    const expr_type = tc.inferExprType(s.expr.*) catch {
                        // If type inference fails, default to 8 bytes
                        break :blk @as(i64, 8);
                    };
                    break :blk self.calculateTypeSize(expr_type);
                } else {
                    // No type checker available, use default
                    break :blk @as(i64, 8);
                }
            },
            .sizeof_type => |s| blk: {
                // Calculate size of the type
                break :blk self.calculateTypeSize(s.type);
            },
            .offset => |o| blk: {
                // Calculate offset of member in type
                if (self.type_layouts) |layouts| {
                    const type_name = switch (o.type) {
                        .named => |name| name,
                        else => {
                            break :blk self.calculateMemberOffsetFallback(o.member);
                        },
                    };

                    if (layouts.get(type_name)) |layout| {
                        if (layout.getMemberOffset(o.member)) |offset| {
                            break :blk @as(i64, @intCast(offset));
                        }
                    }
                }

                // Fallback
                break :blk self.calculateMemberOffsetFallback(o.member);
            },
            else => unreachable,
        };

        return .{ .constant = .{ .int = size } };
    }

    /// Calculate size of a type
    fn calculateTypeSize(self: *IRBuilder, typ: ast.Type) i64 {
        return switch (typ) {
            .i0, .u0 => 0,
            .i8, .u8 => 1,
            .i16, .u16 => 2,
            .i32, .u32 => 4,
            .i64, .u64, .f64, .bool => 8, // Bool is 8 bytes (I64)
            .pointer => 8, // Pointers are always 8 bytes on x64
            .array => |arr| blk: {
                const elem_size = self.calculateTypeSize(arr.element_type.*);
                if (arr.size) |size| {
                    break :blk elem_size * @as(i64, @intCast(size));
                } else {
                    // Unsized array defaults to pointer size
                    break :blk 8;
                }
            },
            .named => |name| blk: {
                // Look up actual size from type layouts
                if (self.type_layouts) |layouts| {
                    if (layouts.get(name)) |layout| {
                        break :blk @as(i64, @intCast(layout.total_size));
                    }
                }
                // Default to 8 bytes if layout not found
                break :blk 8;
            },
            .function => 8, // Function pointers
        };
    }

    // ========================================================================
    // Type Conversion
    // ========================================================================

    fn typeToString(self: *IRBuilder, typ: ast.Type) ?[]const u8 {
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
            .bool => "Bool",
            .pointer => |ptr| {
                // Format as "T*" where T is the pointed-to type
                if (self.typeToString(ptr.*)) |inner| {
                    const result = std.fmt.allocPrint(self.allocator, "{s}*", .{inner}) catch return null;
                    self.allocated_type_hints.append(self.allocator, result) catch return null;
                    return result;
                }
                return "PTR"; // Fallback for complex pointer types
            },
            .array => |arr| {
                // Format as "T[n]" or "T[]"
                if (self.typeToString(arr.element_type.*)) |elem_type| {
                    const result = if (arr.size) |size|
                        std.fmt.allocPrint(self.allocator, "{s}[{d}]", .{ elem_type, size }) catch return null
                    else
                        std.fmt.allocPrint(self.allocator, "{s}[]", .{elem_type}) catch return null;
                    self.allocated_type_hints.append(self.allocator, result) catch return null;
                    return result;
                }
                return "ARRAY"; // Fallback
            },
            .named => |name| name,
            .function => "FUNC",
        };
    }

    pub fn finish(self: *IRBuilder) !ir.Module {
        const module = self.module;
        self.module = try ir.Module.init(self.allocator);
        return module;
    }
};
