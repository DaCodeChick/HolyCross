const std = @import("std");
const x64 = @import("x64.zig");
const assembler = @import("assembler.zig");

const X64Assembler = x64.X64Assembler;
const Register = x64.Register;

fn freeInstructions(allocator: std.mem.Allocator, instructions: []assembler.Instruction) void {
    for (instructions) |instr| {
        allocator.free(instr.operands);
    }
    allocator.free(instructions);
}

test "x64 register parsing" {
    try std.testing.expect(Register.fromString("RAX") == .RAX);
    try std.testing.expect(Register.fromString("RBX") == .RBX);
    try std.testing.expect(Register.fromString("R8") == .R8);
    try std.testing.expect(Register.fromString("R15") == .R15);
    try std.testing.expect(Register.fromString("EAX") == .EAX);
    try std.testing.expect(Register.fromString("AL") == .AL);
    try std.testing.expect(Register.fromString("INVALID") == null);
}

test "x64 register size" {
    try std.testing.expect(Register.RAX.getSize() == .qword);
    try std.testing.expect(Register.EAX.getSize() == .dword);
    try std.testing.expect(Register.AX.getSize() == .word);
    try std.testing.expect(Register.AL.getSize() == .byte);
}

test "x64 parse simple instructions" {
    const allocator = std.testing.allocator;
    
    var asm_impl = X64Assembler.init(allocator);
    defer asm_impl.deinit();
    
    const source =
        \\PUSH RAX
        \\PUSH RBX
        \\POP RBX
        \\POP RAX
        \\RET
    ;
    
    const instructions = try asm_impl.parse(source, allocator);
    defer freeInstructions(allocator, instructions);
    
    try std.testing.expectEqual(@as(usize, 5), instructions.len);
    
    try std.testing.expect(std.mem.eql(u8, instructions[0].mnemonic, "PUSH"));
    try std.testing.expectEqual(@as(usize, 1), instructions[0].operands.len);
    try std.testing.expect(instructions[0].operands[0] == .register);
    
    try std.testing.expect(std.mem.eql(u8, instructions[4].mnemonic, "RET"));
    try std.testing.expectEqual(@as(usize, 0), instructions[4].operands.len);
}

test "x64 parse MOV instructions" {
    const allocator = std.testing.allocator;
    
    var asm_impl = X64Assembler.init(allocator);
    defer asm_impl.deinit();
    
    const source =
        \\MOV RAX, RBX
        \\MOV RCX, 42
        \\MOV RDX, 0x100
    ;
    
    const instructions = try asm_impl.parse(source, allocator);
    defer freeInstructions(allocator, instructions);
    
    try std.testing.expectEqual(@as(usize, 3), instructions.len);
    
    // MOV RAX, RBX
    try std.testing.expect(std.mem.eql(u8, instructions[0].mnemonic, "MOV"));
    try std.testing.expectEqual(@as(usize, 2), instructions[0].operands.len);
    try std.testing.expect(instructions[0].operands[0] == .register);
    try std.testing.expect(instructions[0].operands[1] == .register);
    
    // MOV RCX, 42
    try std.testing.expect(instructions[1].operands[0] == .register);
    try std.testing.expect(instructions[1].operands[1] == .immediate);
    try std.testing.expectEqual(@as(i64, 42), instructions[1].operands[1].immediate.value);
    
    // MOV RDX, 0x100
    try std.testing.expectEqual(@as(i64, 0x100), instructions[2].operands[1].immediate.value);
}

test "x64 parse labels" {
    const allocator = std.testing.allocator;
    
    var asm_impl = X64Assembler.init(allocator);
    defer asm_impl.deinit();
    
    const source =
        \\_FUNCTION::
        \\  PUSH RBP
        \\  MOV RBP, RSP
        \\@@loop:
        \\  CALL some_func
        \\  LOOP @@loop
        \\  POP RBP
        \\  RET
    ;
    
    const instructions = try asm_impl.parse(source, allocator);
    defer freeInstructions(allocator, instructions);
    
    // Check that labels were registered
    try std.testing.expect(asm_impl.labels.contains("_FUNCTION"));
    try std.testing.expect(asm_impl.labels.contains("@@loop"));
    
    const func_label = asm_impl.labels.get("_FUNCTION").?;
    try std.testing.expect(func_label.is_exported);
    try std.testing.expect(!func_label.is_local);
    
    const loop_label = asm_impl.labels.get("@@loop").?;
    try std.testing.expect(loop_label.is_local);
}

test "x64 encode PUSH/POP" {
    const allocator = std.testing.allocator;
    
    var asm_impl = X64Assembler.init(allocator);
    defer asm_impl.deinit();
    
    const source =
        \\PUSH RAX
        \\POP RAX
    ;
    
    const instructions = try asm_impl.parse(source, allocator);
    defer freeInstructions(allocator, instructions);
    
    const code = try asm_impl.encode(instructions, allocator);
    defer allocator.free(code);
    
    // PUSH RAX = 0x50 (RAX is register 0)
    // POP RAX = 0x58
    try std.testing.expectEqual(@as(usize, 2), code.len);
    try std.testing.expectEqual(@as(u8, 0x50), code[0]);
    try std.testing.expectEqual(@as(u8, 0x58), code[1]);
}

test "x64 encode PUSH R8" {
    const allocator = std.testing.allocator;
    
    var asm_impl = X64Assembler.init(allocator);
    defer asm_impl.deinit();
    
    const source = "PUSH R8\n";
    
    const instructions = try asm_impl.parse(source, allocator);
    defer freeInstructions(allocator, instructions);
    
    const code = try asm_impl.encode(instructions, allocator);
    defer allocator.free(code);
    
    // PUSH R8 = REX.B (0x41) + 0x50
    try std.testing.expectEqual(@as(usize, 2), code.len);
    try std.testing.expectEqual(@as(u8, 0x41), code[0]);
    try std.testing.expectEqual(@as(u8, 0x50), code[1]);
}

test "x64 encode MOV reg, reg" {
    const allocator = std.testing.allocator;
    
    var asm_impl = X64Assembler.init(allocator);
    defer asm_impl.deinit();
    
    const source = "MOV RAX, RBX\n";
    
    const instructions = try asm_impl.parse(source, allocator);
    defer freeInstructions(allocator, instructions);
    
    const code = try asm_impl.encode(instructions, allocator);
    defer allocator.free(code);
    
    // MOV RAX, RBX = REX.W (0x48) + 0x89 + ModR/M (0xD8)
    // ModR/M = 11 011 000 = 0xD8 (mod=11, reg=RBX=3, rm=RAX=0)
    try std.testing.expectEqual(@as(usize, 3), code.len);
    try std.testing.expectEqual(@as(u8, 0x48), code[0]); // REX.W
    try std.testing.expectEqual(@as(u8, 0x89), code[1]); // MOV opcode
    try std.testing.expectEqual(@as(u8, 0xD8), code[2]); // ModR/M
}

test "x64 encode MOV reg, imm" {
    const allocator = std.testing.allocator;
    
    var asm_impl = X64Assembler.init(allocator);
    defer asm_impl.deinit();
    
    const source = "MOV RAX, 42\n";
    
    const instructions = try asm_impl.parse(source, allocator);
    defer freeInstructions(allocator, instructions);
    
    const code = try asm_impl.encode(instructions, allocator);
    defer allocator.free(code);
    
    // MOV RAX, imm64 = REX.W (0x48) + 0xB8 + imm64
    try std.testing.expectEqual(@as(usize, 10), code.len);
    try std.testing.expectEqual(@as(u8, 0x48), code[0]); // REX.W
    try std.testing.expectEqual(@as(u8, 0xB8), code[1]); // MOV RAX, imm64
    // Next 8 bytes should be 42 in little-endian
    try std.testing.expectEqual(@as(u8, 42), code[2]);
}
