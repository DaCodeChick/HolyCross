//! Tests for the assembler architecture abstraction

const std = @import("std");
const testing = std.testing;
const assembler_mod = @import("../../assembler.zig");

const X64Assembler = assembler_mod.X64Assembler;
const Assembler = assembler_mod.Assembler;
const OperandSize = assembler_mod.OperandSize;

test "x64 assembler init and deinit" {
    var x64 = X64Assembler.init(testing.allocator);
    defer x64.deinit();
    
    // Should initialize successfully
    try testing.expect(x64.labels.count() == 0);
}

test "x64 register name lookup" {
    var x64 = X64Assembler.init(testing.allocator);
    defer x64.deinit();
    
    // Test 64-bit registers
    try testing.expectEqualStrings("RAX", x64.getRegisterName(0, .qword));
    try testing.expectEqualStrings("RCX", x64.getRegisterName(1, .qword));
    try testing.expectEqualStrings("RDX", x64.getRegisterName(2, .qword));
    try testing.expectEqualStrings("R8", x64.getRegisterName(8, .qword));
    try testing.expectEqualStrings("R15", x64.getRegisterName(15, .qword));
    
    // Test 32-bit registers
    try testing.expectEqualStrings("EAX", x64.getRegisterName(0, .dword));
    try testing.expectEqualStrings("ECX", x64.getRegisterName(1, .dword));
    
    // Test 16-bit registers
    try testing.expectEqualStrings("AX", x64.getRegisterName(0, .word));
    try testing.expectEqualStrings("CX", x64.getRegisterName(1, .word));
    
    // Test 8-bit registers
    try testing.expectEqualStrings("AL", x64.getRegisterName(0, .byte));
    try testing.expectEqualStrings("CL", x64.getRegisterName(1, .byte));
}

test "x64 register ID lookup" {
    var x64 = X64Assembler.init(testing.allocator);
    defer x64.deinit();
    
    // Test 64-bit registers
    try testing.expectEqual(@as(u8, 0), try x64.getRegisterId("RAX"));
    try testing.expectEqual(@as(u8, 1), try x64.getRegisterId("RCX"));
    try testing.expectEqual(@as(u8, 2), try x64.getRegisterId("RDX"));
    try testing.expectEqual(@as(u8, 8), try x64.getRegisterId("R8"));
    
    // Test 32-bit registers
    try testing.expectEqual(@as(u8, 0), try x64.getRegisterId("EAX"));
    try testing.expectEqual(@as(u8, 1), try x64.getRegisterId("ECX"));
    
    // Test invalid register
    try testing.expectError(error.InvalidRegister, x64.getRegisterId("INVALID"));
}

test "x64 assembler as interface" {
    var x64 = X64Assembler.init(testing.allocator);
    defer x64.deinit();
    
    // Convert to interface
    const asm_interface = x64.asAssembler();
    
    // Test interface methods
    try testing.expectEqualStrings("RAX", asm_interface.getRegisterName(0, .qword));
    try testing.expectEqual(@as(u8, 0), try asm_interface.getRegisterId("RAX"));
    
    // Test parse (returns empty for now)
    const instructions = try asm_interface.parse("MOV RAX, RBX", testing.allocator);
    try testing.expectEqual(@as(usize, 0), instructions.len);
    
    // Test encode (returns empty for now)
    const code = try asm_interface.encode(instructions, testing.allocator);
    try testing.expectEqual(@as(usize, 0), code.len);
}

test "architecture abstraction - multiple architectures" {
    // This test demonstrates how the interface allows switching architectures
    var x64 = X64Assembler.init(testing.allocator);
    defer x64.deinit();
    
    const asm_interface = x64.asAssembler();
    
    // The same interface can be used regardless of architecture
    const reg_name = asm_interface.getRegisterName(0, .qword);
    try testing.expectEqualStrings("RAX", reg_name);
    
    // Future: ARM64Assembler, RISCV64Assembler, etc. would work the same way
}
