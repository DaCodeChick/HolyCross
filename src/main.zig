const std = @import("std");
const GlobalAllocator = @import("allocator.zig");
const preprocessor = @import("preprocessor/preprocessor.zig");
const lexer = @import("lexer/lexer.zig");
const parser = @import("parser/parser.zig");
const ast = @import("parser/ast.zig");
const semantic = @import("semantic/symbol_table.zig");
const type_checker = @import("semantic/type_checker.zig");
const analyzer = @import("semantic/analyzer.zig");
const codegen_test = @import("codegen/tests/codegen_tests.zig");
const Compiler = @import("codegen/compiler.zig").Compiler;
const target_module = @import("codegen/target.zig");
const Target = target_module.Target;
const TargetConfig = target_module.TargetConfig;

pub fn main(init: std.process.Init) !void {
    // Use DebugAllocator in debug builds, ArenaAllocator in release builds
    var gpa = GlobalAllocator.init();
    defer GlobalAllocator.deinit(&gpa);
    
    const allocator = GlobalAllocator.allocator(&gpa);
    
    // Create arena for args allocation
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Get command line arguments
    const args = try init.minimal.args.toSlice(arena.allocator());

    // Parse arguments
    if (args.len < 2) {
        printUsage(args[0]);
        return;
    }

    // Parse flags
    var emit_asm_only = false;
    var compile_only = false; // -c flag: compile to object file
    var input_file: []const u8 = "";
    var output_file: []const u8 = "";
    var target: Target = .native_x64_linux;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-S")) {
            emit_asm_only = true;
        } else if (std.mem.eql(u8, arg, "-c")) {
            compile_only = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i < args.len) {
                output_file = args[i];
            } else {
                std.debug.print("Error: -o flag requires an argument\n", .{});
                return error.MissingOutputFile;
            }
        } else if (std.mem.startsWith(u8, arg, "--target=")) {
            const target_str = arg["--target=".len..];
            target = Target.fromString(target_str) catch {
                std.debug.print("Error: Invalid target '{s}'\n", .{target_str});
                std.debug.print("Valid targets: native, templeos, zealos\n", .{});
                return error.InvalidTarget;
            };
        } else if (input_file.len == 0) {
            input_file = arg;
        } else if (output_file.len == 0) {
            output_file = arg;
        }
    }

    if (input_file.len == 0) {
        printUsage(args[0]);
        return;
    }

    if (output_file.len == 0) {
        // Extract base name from input file (strip directory and .hc extension)
        const basename = blk: {
            const last_slash = std.mem.lastIndexOfScalar(u8, input_file, '/') orelse 0;
            const start = if (last_slash > 0) last_slash + 1 else 0;
            const name_with_ext = input_file[start..];
            
            if (std.mem.endsWith(u8, name_with_ext, ".hc")) {
                break :blk name_with_ext[0..name_with_ext.len - 3];
            } else if (std.mem.endsWith(u8, name_with_ext, ".HC")) {
                break :blk name_with_ext[0..name_with_ext.len - 3];
            }
            break :blk name_with_ext;
        };
        
        if (emit_asm_only) {
            output_file = try std.fmt.allocPrint(arena.allocator(), "{s}.s", .{basename});
        } else if (compile_only) {
            output_file = try std.fmt.allocPrint(arena.allocator(), "{s}.o", .{basename});
        } else {
            // Use default extension based on target
            const extension = target.defaultExtension();
            if (extension.len > 0) {
                output_file = try std.fmt.allocPrint(arena.allocator(), "{s}{s}", .{ basename, extension });
            } else {
                output_file = basename;
            }
        }
    }

    // Print info
    std.debug.print("HolyCross Compiler v0.1.0\n", .{});
    std.debug.print("Target: {s}\n", .{target.toString()});
    std.debug.print("Compiling: {s} -> {s}\n\n", .{ input_file, output_file });

    // Read input file
    const cwd = std.Io.Dir.cwd();
    const source = try cwd.readFileAlloc(init.io, input_file, allocator, std.Io.Limit.limited(1024 * 1024)); // Max 1MB
    defer allocator.free(source);

    // Phase 0: Preprocessing (conditional compilation)
    std.debug.print("[Phase 0] Preprocessing...\n", .{});
    var preproc = try preprocessor.Preprocessor.initWithIo(allocator, source, input_file, &init.io);
    defer preproc.deinit();
    const processed_source = try preproc.process();
    defer allocator.free(processed_source);

    // Phase 1: Lexical analysis
    std.debug.print("[Phase 1] Lexical Analysis...\n", .{});
    var lex = lexer.Lexer.init(allocator, processed_source);

    // Phase 2: Parsing
    std.debug.print("[Phase 2] Parsing...\n", .{});
    var pars = try parser.Parser.init(allocator, &lex);
    defer pars.deinit();

    var program = pars.parse() catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return err;
    };
    defer program.deinit();

    // Phase 3: Semantic analysis
    std.debug.print("[Phase 3] Semantic Analysis...\n", .{});
    var anal = analyzer.Analyzer.init(allocator);
    anal.initTypeChecker(); // Must be called after analyzer is at final location
    defer anal.deinit();

    anal.analyze(program) catch |err| {
        std.debug.print("Semantic analysis error: {}\n", .{err});
        if (anal.errors.items.len > 0) {
            std.debug.print("Errors:\n", .{});
            for (anal.errors.items) |error_item| {
                std.debug.print("  {s}:{}:{}: {s}\n", .{ 
                    input_file, 
                    error_item.loc.line, 
                    error_item.loc.column, 
                    error_item.message 
                });
            }
        }
        return err;
    };

    // Phase 4: Code generation
    std.debug.print("[Phase 4] Code Generation...\n", .{});
    const target_config = TargetConfig.init(target);
    var compiler = Compiler.init(allocator, target_config);
    defer compiler.deinit();

    if (emit_asm_only) {
        // Generate assembly only (-S flag)
        const asm_code = try compiler.compileToAssembly(&program, &anal.type_checker, &anal.type_layouts);
        defer allocator.free(asm_code);

        const asm_file = try cwd.createFile(init.io, output_file, .{});
        defer asm_file.close(init.io);
        
        var write_buffer: [8192]u8 = undefined;
        var buffered_writer = asm_file.writer(init.io, &write_buffer);
        defer buffered_writer.flush() catch {};
        try buffered_writer.interface.writeAll(asm_code);

        std.debug.print("\n✓ Assembly generation successful!\n", .{});
        std.debug.print("Output: {s}\n", .{output_file});
    } else if (compile_only) {
        // Generate object file only (-c flag)
        try compiler.compileToObject(&program, output_file, &anal.type_checker, &anal.type_layouts, init.io);

        std.debug.print("\n✓ Object file generation successful!\n", .{});
        std.debug.print("Output: {s}\n", .{output_file});
    } else {
        // Generate executable
        try compiler.compileToExecutable(&program, output_file, &anal.type_checker, &anal.type_layouts, init.io);

        std.debug.print("\n✓ Compilation successful!\n", .{});
        std.debug.print("Output: {s}\n", .{output_file});
    }
}

fn printUsage(program_name: []const u8) void {
    std.debug.print("Usage: {s} [options] <input.hc> [output]\n", .{program_name});
    std.debug.print("\n", .{});
    std.debug.print("HolyC Cross-Compiler - Compile HolyC to native binaries\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  -S                 Emit assembly code only\n", .{});
    std.debug.print("  --target=<target>  Set compilation target\n", .{});
    std.debug.print("                     Valid targets: native, templeos, zealos\n", .{});
    std.debug.print("                     Default: native\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Arguments:\n", .{});
    std.debug.print("  <input.hc>         HolyC source file to compile\n", .{});
    std.debug.print("  [output]           Output file name (default depends on target)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Examples:\n", .{});
    std.debug.print("  {s} hello.hc\n", .{program_name});
    std.debug.print("  {s} program.hc myprogram\n", .{program_name});
    std.debug.print("  {s} -S hello.hc hello.s\n", .{program_name});
    std.debug.print("  {s} --target=templeos hello.hc hello.BIN\n", .{program_name});
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
