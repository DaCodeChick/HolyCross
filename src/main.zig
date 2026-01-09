const std = @import("std");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse arguments
    if (args.len < 2) {
        printUsage(args[0]);
        return;
    }

    const input_file = args[1];
    const output_file = if (args.len >= 3) args[2] else "a.out";

    // Print info
    std.debug.print("HolyC Cross-Compiler v0.1.0\n", .{});
    std.debug.print("Compiling: {s} -> {s}\n", .{ input_file, output_file });

    // Read input file
    const file = try std.fs.cwd().openFile(input_file, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024); // Max 1MB
    defer allocator.free(source);

    // Phase 0: Lexical analysis (tokenization)
    // TODO: Implement lexer
    std.debug.print("\n[Phase 0] Lexical Analysis\n", .{});
    std.debug.print("Source length: {} bytes\n", .{source.len});
    std.debug.print("Status: Not yet implemented\n", .{});

    // TODO: Phase 1: Parsing
    // TODO: Phase 2: Semantic analysis
    // TODO: Phase 3: Code generation
    // TODO: Phase 4: Binary output

    std.debug.print("\nCompilation incomplete - compiler under development!\n", .{});
}

fn printUsage(program_name: []const u8) void {
    std.debug.print("Usage: {s} <input.hc> [output]\n", .{program_name});
    std.debug.print("\n", .{});
    std.debug.print("HolyC Cross-Compiler - Compile HolyC to native binaries\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  <input.hc>   HolyC source file to compile\n", .{});
    std.debug.print("  [output]     Output file name (default: a.out)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Examples:\n", .{});
    std.debug.print("  {s} hello.hc\n", .{program_name});
    std.debug.print("  {s} program.hc myprogram\n", .{program_name});
}

test "main module" {
    // Basic test to ensure module compiles
    const testing = std.testing;
    try testing.expect(true);
}
