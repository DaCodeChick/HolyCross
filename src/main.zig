const std = @import("std");
const lexer = @import("lexer/lexer.zig");
const parser = @import("parser/parser.zig");
const ast = @import("parser/ast.zig");
const semantic = @import("semantic/symbol_table.zig");
const type_checker = @import("semantic/type_checker.zig");
const analyzer = @import("semantic/analyzer.zig");
const codegen_test = @import("codegen/codegen_test.zig");
const Compiler = @import("codegen/compiler.zig").Compiler;

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
    std.debug.print("HolyCross Compiler v0.1.0\n", .{});
    std.debug.print("Compiling: {s} -> {s}\n\n", .{ input_file, output_file });

    // Read input file
    const file = try std.fs.cwd().openFile(input_file, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024); // Max 1MB
    defer allocator.free(source);

    // Phase 1: Lexical analysis
    std.debug.print("[Phase 1] Lexical Analysis...\n", .{});
    var lex = lexer.Lexer.init(allocator, source);

    // Phase 2: Parsing
    std.debug.print("[Phase 2] Parsing...\n", .{});
    var pars = try parser.Parser.init(allocator, &lex);

    var program = pars.parse() catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return err;
    };
    defer program.deinit();

    // Phase 3: Semantic analysis
    std.debug.print("[Phase 3] Semantic Analysis...\n", .{});
    var anal = analyzer.Analyzer.init(allocator);
    defer anal.deinit();

    anal.analyze(program) catch |err| {
        std.debug.print("Semantic analysis error: {}\n", .{err});
        if (anal.errors.items.len > 0) {
            std.debug.print("Errors:\n", .{});
            for (anal.errors.items) |error_item| {
                std.debug.print("  {s}\n", .{error_item.message});
            }
        }
        return err;
    };

    // Phase 4: Code generation
    std.debug.print("[Phase 4] Code Generation...\n", .{});
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    try compiler.compileToExecutable(&program, output_file);

    std.debug.print("\n✓ Compilation successful!\n", .{});
    std.debug.print("Output: {s}\n", .{output_file});
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

// Import all tests from sub-modules
test {
    _ = lexer;
    _ = parser;
    _ = ast;
    _ = semantic;
    _ = type_checker;
    _ = analyzer;
    _ = codegen_test;
}
