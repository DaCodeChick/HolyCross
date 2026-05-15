const std = @import("std");
const lib = @import("holycross");
const X64Assembler = lib.assembler.X64Assembler;
const Preprocessor = lib.preprocessor.Preprocessor;

/// hcas - HolyC Assembler
/// Standalone assembler tool for HolyC/TempleOS-style x64 assembly
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    
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
    
    // Parse flags and options
    var input_file: []const u8 = "";
    var output_file: ?[]const u8 = null;
    var output_format: OutputFormat = .elf_object;
    var listing_file: ?[]const u8 = null;
    
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage(args[0]);
            return;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            printVersion();
            return;
        } else if (std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i < args.len) {
                output_file = args[i];
            } else {
                std.debug.print("Error: -o flag requires an argument\n", .{});
                return error.MissingOutputFile;
            }
        } else if (std.mem.eql(u8, arg, "-f")) {
            i += 1;
            if (i < args.len) {
                const format_str = args[i];
                output_format = OutputFormat.fromString(format_str) catch {
                    std.debug.print("Error: Invalid output format '{s}'\n", .{format_str});
                    std.debug.print("Valid formats: elf, bin, hex\n", .{});
                    return error.InvalidFormat;
                };
            } else {
                std.debug.print("Error: -f flag requires an argument\n", .{});
                return error.MissingFormat;
            }
        } else if (std.mem.eql(u8, arg, "-l")) {
            i += 1;
            if (i < args.len) {
                listing_file = args[i];
            } else {
                std.debug.print("Error: -l flag requires an argument\n", .{});
                return error.MissingListingFile;
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown flag '{s}'\n", .{arg});
            return error.UnknownFlag;
        } else if (input_file.len == 0) {
            input_file = arg;
        } else {
            std.debug.print("Error: Multiple input files not supported\n", .{});
            return error.MultipleInputFiles;
        }
    }
    
    if (input_file.len == 0) {
        std.debug.print("Error: No input file specified\n", .{});
        printUsage(args[0]);
        return error.NoInputFile;
    }
    
    // Set default output file if not specified
    if (output_file == null) {
        output_file = switch (output_format) {
            .elf_object => "a.o",
            .raw_binary => "a.bin",
            .hex_dump => "a.hex",
        };
    }
    
    // Read input file
    const cwd = std.Io.Dir.cwd();
    const source = try cwd.readFileAlloc(init.io, input_file, allocator, std.Io.Limit.limited(10 * 1024 * 1024)); // Max 10MB
    defer allocator.free(source);
    
    std.debug.print("HolyC Assembler v0.1.0\n", .{});
    std.debug.print("Assembling: {s} -> {s}\n\n", .{ input_file, output_file.? });
    
    // Preprocess the source (handle #define, #assert, etc.)
    var preprocessor = try Preprocessor.initWithIo(allocator, source, input_file, &init.io);
    defer preprocessor.deinit();
    
    const processed_source = try preprocessor.process();
    defer allocator.free(processed_source);
    
    // Initialize assembler
    var asm_ctx = X64Assembler.init(allocator);
    defer asm_ctx.deinit();
    
    // Parse assembly source
    std.debug.print("[1/3] Parsing assembly...\n", .{});
    const instructions = asm_ctx.parse(processed_source, allocator) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return err;
    };
    defer {
        // Free operands and directive data for each instruction
        for (instructions) |instr| {
            allocator.free(instr.operands);
            
            // Free directive data if present
            if (instr.directive) |directive| {
                switch (directive) {
                    .data => |data| {
                        allocator.free(data.values);
                    },
                    .import_symbols => |symbols| {
                        allocator.free(symbols);
                    },
                    else => {},
                }
            }
        }
        allocator.free(instructions);
    }
    
    std.debug.print("      Parsed {} instructions\n", .{instructions.len});
    
    // Encode to machine code
    std.debug.print("[2/3] Encoding to machine code...\n", .{});
    const machine_code = asm_ctx.encode(instructions, allocator) catch |err| {
        std.debug.print("Encode error: {}\n", .{err});
        return err;
    };
    defer allocator.free(machine_code);
    
    std.debug.print("      Generated {} bytes\n", .{machine_code.len});
    
    // Write output
    std.debug.print("[3/3] Writing output...\n", .{});
    switch (output_format) {
        .elf_object => {
            std.debug.print("Error: ELF object file output not yet implemented\n", .{});
            return error.NotImplemented;
        },
        .raw_binary => {
            const out_file = try cwd.createFile(init.io, output_file.?, .{});
            defer out_file.close(init.io);
            try out_file.writeStreamingAll(init.io, machine_code);
        },
        .hex_dump => {
            const out_file = try cwd.createFile(init.io, output_file.?, .{});
            defer out_file.close(init.io);
            
            // Create buffered writer
            var write_buffer: [8192]u8 = undefined;
            var writer = out_file.writer(init.io, &write_buffer);
            
            var offset: usize = 0;
            while (offset < machine_code.len) {
                const chunk_size = @min(16, machine_code.len - offset);
                const chunk = machine_code[offset..][0..chunk_size];
                
                // Format: "00000000: 48 89 E5 48 83 EC 10\n"
                try writer.interface.print("{X:0>8}: ", .{offset});
                for (chunk) |byte| {
                    try writer.interface.print("{X:0>2} ", .{byte});
                }
                try writer.interface.print("\n", .{});
                
                offset += chunk_size;
            }
            
            try writer.flush();
        },
    }
    
    // Generate listing file if requested
    if (listing_file) |list_path| {
        const list_file = try cwd.createFile(init.io, list_path, .{});
        defer list_file.close(init.io);
        
        try list_file.writeStreamingAll(init.io, "Assembly Listing\n");
        try list_file.writeStreamingAll(init.io, "================\n\n");
        
        for (instructions, 0..) |instr, idx| {
            var line_buf: [256]u8 = undefined;
            const line = try std.fmt.bufPrint(&line_buf, "{d:4}: {s}\n", .{ idx, instr.mnemonic });
            try list_file.writeStreamingAll(init.io, line);
        }
    }
    
    std.debug.print("\n✓ Assembly successful!\n", .{});
    std.debug.print("Output: {s}\n", .{output_file.?});
    if (listing_file) |list_path| {
        std.debug.print("Listing: {s}\n", .{list_path});
    }
}

const OutputFormat = enum {
    elf_object,
    raw_binary,
    hex_dump,
    
    fn fromString(s: []const u8) !OutputFormat {
        if (std.mem.eql(u8, s, "elf") or std.mem.eql(u8, s, "obj") or std.mem.eql(u8, s, "o")) {
            return .elf_object;
        } else if (std.mem.eql(u8, s, "bin") or std.mem.eql(u8, s, "binary")) {
            return .raw_binary;
        } else if (std.mem.eql(u8, s, "hex")) {
            return .hex_dump;
        }
        return error.InvalidFormat;
    }
};

fn printVersion() void {
    std.debug.print("hcas v0.1.0 - HolyC Assembler\n", .{});
    std.debug.print("Part of the HolyCross toolchain\n", .{});
    std.debug.print("Target: x64 (AMD64)\n", .{});
}

fn printUsage(program_name: []const u8) void {
    std.debug.print("Usage: {s} [options] <input.asm>\n", .{program_name});
    std.debug.print("\n", .{});
    std.debug.print("HolyC Assembler - Assemble TempleOS-style x64 assembly\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  -o <file>          Write output to <file> (default: a.o)\n", .{});
    std.debug.print("  -f <format>        Output format: elf, bin, hex (default: elf)\n", .{});
    std.debug.print("  -l <file>          Generate listing file\n", .{});
    std.debug.print("  -h, --help         Show this help message\n", .{});
    std.debug.print("  -v, --version      Show version information\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Output Formats:\n", .{});
    std.debug.print("  elf    ELF object file (.o) for linking\n", .{});
    std.debug.print("  bin    Raw binary machine code\n", .{});
    std.debug.print("  hex    Hexadecimal dump of machine code\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Examples:\n", .{});
    std.debug.print("  {s} code.asm -o code.o\n", .{program_name});
    std.debug.print("  {s} code.asm -f bin -o code.bin\n", .{program_name});
    std.debug.print("  {s} code.asm -f hex -o code.hex -l code.lst\n", .{program_name});
    std.debug.print("\n", .{});
    std.debug.print("Supported Syntax:\n", .{});
    std.debug.print("  - TempleOS-style assembly (MOV, ADD, SUB, etc.)\n", .{});
    std.debug.print("  - Labels: label:, @@local:, exported::\n", .{});
    std.debug.print("  - Comments: // comment\n", .{});
}
