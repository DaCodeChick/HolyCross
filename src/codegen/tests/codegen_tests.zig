const std = @import("std");
const ir = @import("../ir.zig");
const ir_builder = @import("../ir_builder.zig");
const x64 = @import("../x64.zig");
const ast = @import("../../parser/ast.zig");
const testing = std.testing;

test "IRBuilder: simple function" {
    const allocator = testing.allocator;

    // Create a simple AST: U0 Main() { }
    var builder = try ir_builder.IRBuilder.init(allocator, null, null);
    defer builder.deinit();

    const func = @as(ast.Decl, .{ .function = .{
        .return_type = .u0,
        .name = "Main",
        .params = &[_]ast.Param{},
        .is_variadic = false,
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

    var builder = try ir_builder.IRBuilder.init(allocator, null, null);
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
        .is_variadic = false,
        .body = block_stmt,
        .attributes = .{},
        .loc = .{ .line = 1, .column = 1 },
    } });

    try builder.buildDeclaration(func);

    const module = try builder.finish();
    var mod = module;
    defer mod.deinit();

    // Verify we have a function and the string literal was added to the module
    try testing.expectEqual(@as(usize, 1), mod.functions.items.len);
    try testing.expect(mod.string_table.items.len > 0);
    
    // Verify the string literal is in the string table
    var found = false;
    for (mod.string_table.items) |str| {
        if (std.mem.eql(u8, str, "Hello, World!\\n")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
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

    // Just verify we can create module without crashing
    // TODO: Fix Writer API usage for Zig 0.16.0 and re-enable print test
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

    // Verify output contains function declaration (TempleOS syntax)
    try testing.expect(std.mem.find(u8, output, "test_func:") != null or 
                      std.mem.find(u8, output, "_test_func::") != null);
    try testing.expect(std.mem.find(u8, output, "PUSH") != null);
    try testing.expect(std.mem.find(u8, output, "RET") != null);
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

    // Verify output contains constant load (TempleOS syntax)
    try testing.expect(std.mem.find(u8, output, "MOV\tRAX,42") != null or
                      std.mem.find(u8, output, "MOV RAX,42") != null);

    // Print output for inspection (commented out normally)
    // std.debug.print("\n=== Generated x64 Assembly ===\n{s}\n", .{output});
}
