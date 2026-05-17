const std = @import("std");
const lib = @import("holycross");
const Preprocessor = lib.preprocessor.Preprocessor;
const GlobalAllocator = lib.allocator;

const Define = struct {
    name: []const u8,
    value: []const u8,
};

/// holypp - HolyC Preprocessor
/// Standalone preprocessor tool for HolyC source files
pub fn main(init: std.process.Init) !void {
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
    
    // Parse flags and options
    var input_file: []const u8 = "";
    var output_file: ?[]const u8 = null;
    var defines: std.ArrayList(Define) = .empty;
    var include_dirs: std.ArrayList([]const u8) = .empty;
    
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
        } else if (std.mem.startsWith(u8, arg, "-D")) {
            // Handle -D flag: -DNAME or -DNAME=VALUE
            const define_str = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    std.debug.print("Error: -D flag requires an argument\n", .{});
                    return error.MissingDefine;
                }
                break :blk args[i];
            };
            
            // Split on '=' to get name and value
            if (std.mem.indexOfScalar(u8, define_str, '=')) |eq_pos| {
                const name = define_str[0..eq_pos];
                const value = define_str[eq_pos + 1 ..];
                try defines.append(arena.allocator(), .{ .name = name, .value = value });
            } else {
                // No value, define as "1"
                try defines.append(arena.allocator(), .{ .name = define_str, .value = "1" });
            }
        } else if (std.mem.startsWith(u8, arg, "-I")) {
            // Handle -I flag: -Ipath or -I path
            const include_dir = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    std.debug.print("Error: -I flag requires an argument\n", .{});
                    return error.MissingIncludeDir;
                }
                break :blk args[i];
            };
            try include_dirs.append(arena.allocator(), include_dir);
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
    
    // Read input file
    const cwd = std.Io.Dir.cwd();
    const source = try cwd.readFileAlloc(init.io, input_file, allocator, std.Io.Limit.limited(10 * 1024 * 1024)); // Max 10MB
    defer allocator.free(source);
    
    // Initialize preprocessor
    var preproc = try Preprocessor.initWithIo(allocator, source, input_file, &init.io);
    defer preproc.deinit();
    
    // Add command-line defines
    for (defines.items) |define| {
        const name_copy = try allocator.dupe(u8, define.name);
        const value_copy = try allocator.dupe(u8, define.value);
        try preproc.defines.put(name_copy, value_copy);
    }
    
    // Process the file
    const processed_source = try preproc.process();
    defer allocator.free(processed_source);
    
    // Output the result
    if (output_file) |out_path| {
        // Write to file using buffered IO
        const out_file = try cwd.createFile(init.io, out_path, .{});
        defer out_file.close(init.io);
        
        var write_buffer: [8192]u8 = undefined;
        var buffered_writer = out_file.writer(init.io, &write_buffer);
        defer buffered_writer.flush() catch {};
        try buffered_writer.interface.writeAll(processed_source);
        
        std.debug.print("Preprocessing complete: {s} -> {s}\n", .{ input_file, out_path });
    } else {
        // Write to stdout - for now, just use print
        std.debug.print("{s}", .{processed_source});
    }
}

fn printVersion() void {
    std.debug.print("hcpp v0.1.0 - HolyC Preprocessor\n", .{});
    std.debug.print("Part of the HolyCross toolchain\n", .{});
}

fn printUsage(program_name: []const u8) void {
    std.debug.print("Usage: {s} [options] <input.HC>\n", .{program_name});
    std.debug.print("\n", .{});
    std.debug.print("HolyC Preprocessor - Process HolyC source files\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  -o <file>          Write output to <file> (default: stdout)\n", .{});
    std.debug.print("  -D<name>[=<value>] Define a macro (default value: 1)\n", .{});
    std.debug.print("  -I<dir>            Add directory to include search path\n", .{});
    std.debug.print("  -h, --help         Show this help message\n", .{});
    std.debug.print("  -v, --version      Show version information\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Examples:\n", .{});
    std.debug.print("  {s} input.HC -o output.i\n", .{program_name});
    std.debug.print("  {s} -DDEBUG -DVERSION=2 input.HC\n", .{program_name});
    std.debug.print("  {s} -I/usr/include -I./lib input.HC -o output.i\n", .{program_name});
    std.debug.print("\n", .{});
    std.debug.print("Supported Directives:\n", .{});
    std.debug.print("  #define, #include, #ifdef, #ifndef, #else, #endif\n", .{});
    std.debug.print("  #ifaot, #ifjit, #exe\n", .{});
}
