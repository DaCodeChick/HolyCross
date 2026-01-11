const std = @import("std");
const ir = @import("../ir.zig");
const ir_builder = @import("../ir_builder.zig");
const x64 = @import("../x64.zig");
const ast = @import("../../parser/ast.zig");
const testing = std.testing;

test "IRBuilder: simple function" {
    const allocator = testing.allocator;

    // Create a simple AST: U0 Main() { }
    var builder = try ir_builder.IRBuilder.init(allocator);
    defer builder.deinit();

    const func = @as(ast.Decl, .{ .function = .{
        .return_type = .u0,
        .name = "Main",
        .params = &[_]ast.Param{},
        .body = null,
        .attributes = .{},
        .loc = .{ .line = 1, .column = 1 },
    } });

    try builder.buildDeclaration(func);

    const module = try builder.finish();
    var mod = module;
    defer mod.deinit();

    // Verify function was created
    try testing.expectEqual(@as(usize, 1), mod.functions.items.len);
    try testing.expectEqualStrings("Main", mod.functions.items[0].name);
}

test "IRBuilder: function with string expression" {
    const allocator = testing.allocator;

    var builder = try ir_builder.IRBuilder.init(allocator);
    defer builder.deinit();

    // Create AST for: U0 Main() { "Hello, World!\n"; }
    const string_expr = ast.Expr{ .string = .{
        .value = "Hello, World!\\n",
        .loc = .{ .line = 2, .column = 5 },
    } };

    const expr_stmt = ast.Stmt{ .expr = .{
        .expr = string_expr,
        .loc = .{ .line = 2, .column = 5 },
    } };

    const stmts = try allocator.alloc(ast.Stmt, 1);
    defer allocator.free(stmts);
    stmts[0] = expr_stmt;

    const block_stmt = ast.Stmt{ .block = .{
        .stmts = stmts,
        .loc = .{ .line = 1, .column = 13 },
    } };

    const func = @as(ast.Decl, .{ .function = .{
        .return_type = .u0,
        .name = "Main",
        .params = &[_]ast.Param{},
        .body = block_stmt,
        .attributes = .{},
        .loc = .{ .line = 1, .column = 1 },
    } });

    try builder.buildDeclaration(func);

    const module = try builder.finish();
    var mod = module;
    defer mod.deinit();

    // Verify we have a print instruction
    try testing.expectEqual(@as(usize, 1), mod.functions.items.len);
    const ir_func = &mod.functions.items[0];
    try testing.expect(ir_func.blocks.items.len > 0);

    var has_print = false;
    for (ir_func.blocks.items) |block| {
        for (block.instructions.items) |instr| {
            if (instr.opcode == .print) {
                has_print = true;
            }
        }
    }
    try testing.expect(has_print);
}

test "IR: print module" {
    const allocator = testing.allocator;

    var module = try ir.Module.init(allocator);
    defer module.deinit();

    const func = try module.createFunction("test_func");
    func.param_count = 0;

    const block = try func.createBlock();
    try block.instructions.append(allocator, .{
        .opcode = .load_const,
        .dest = .{ .temp = 0 },
        .src1 = .{ .constant = .{ .int = 42 } },
        .type_hint = "I64",
    });

    try block.instructions.append(allocator, .{
        .opcode = .ret_val,
        .src1 = .{ .temp = 0 },
    });

    // Just verify we can print without crashing
    const empty = try allocator.alloc(u8, 0);
    var buffer = std.ArrayList(u8).fromOwnedSlice(empty);
    defer buffer.deinit(allocator);
    try module.print(buffer.writer(allocator));
}

test "X64: generate simple function" {
    const allocator = testing.allocator;

    var module = try ir.Module.init(allocator);
    defer module.deinit();

    const func = try module.createFunction("test_func");
    func.param_count = 0;

    const block = try func.createBlock();
    try block.instructions.append(allocator, .{
        .opcode = .ret,
    });

    var gen = try x64.X64Generator.init(allocator);
    defer gen.deinit();

    try gen.generateFromIR(&module);
    const output = gen.getOutput();

    // Verify output contains function declaration
    try testing.expect(std.mem.indexOf(u8, output, "test_func:") != null);
    try testing.expect(std.mem.indexOf(u8, output, "push rbp") != null);
    try testing.expect(std.mem.indexOf(u8, output, "ret") != null);
}

test "X64: generate function with constant" {
    const allocator = testing.allocator;

    var module = try ir.Module.init(allocator);
    defer module.deinit();

    const func = try module.createFunction("get_fortytwo");
    func.param_count = 0;
    func.temp_count = 1;

    const block = try func.createBlock();
    try block.instructions.append(allocator, .{
        .opcode = .load_const,
        .dest = .{ .temp = 0 },
        .src1 = .{ .constant = .{ .int = 42 } },
    });
    try block.instructions.append(allocator, .{
        .opcode = .ret_val,
        .src1 = .{ .temp = 0 },
    });

    var gen = try x64.X64Generator.init(allocator);
    defer gen.deinit();

    try gen.generateFromIR(&module);
    const output = gen.getOutput();

    // Verify output contains constant load
    try testing.expect(std.mem.indexOf(u8, output, "mov rax, 42") != null);

    // Print output for inspection (commented out normally)
    // std.debug.print("\n=== Generated x64 Assembly ===\n{s}\n", .{output});
}
