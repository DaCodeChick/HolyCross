const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const ir_builder = @import("ir_builder.zig");
const x64 = @import("x64.zig");
const ast = @import("../parser/ast.zig");
const type_checker_module = @import("../semantic/type_checker.zig");
const type_layout_module = @import("../semantic/type_layout.zig");
const target_module = @import("target.zig");
const templeos_bin = @import("templeos_bin.zig");
const x64_machine_code = @import("x64_machine_code.zig");

const TypeChecker = type_checker_module.TypeChecker;
const TypeLayout = type_layout_module.TypeLayout;
const Target = target_module.Target;
const TargetConfig = target_module.TargetConfig;

/// Compiler - orchestrates the compilation pipeline
pub const Compiler = struct {
    allocator: Allocator,
    target_config: TargetConfig,

    pub fn init(allocator: Allocator, target_config: TargetConfig) Compiler {
        return .{
            .allocator = allocator,
            .target_config = target_config,
        };
    }

    /// Compile AST to x64 assembly string
    pub fn compileToAssembly(
        self: *Compiler,
        program: *const ast.Program,
        type_checker: ?*TypeChecker,
        type_layouts: ?*const std.StringHashMap(TypeLayout),
    ) ![]const u8 {
        // Build IR from AST
        var builder = try ir_builder.IRBuilder.init(self.allocator, type_checker, type_layouts);
        defer builder.deinit();

        try builder.buildFromAST(program);
        const module = try builder.finish();
        var mod = module;
        defer mod.deinit();

        // Generate x64 assembly from IR
        var gen = try x64.X64Generator.init(self.allocator);
        defer gen.deinit();

        try gen.generateFromIR(&mod);

        // Return owned copy of output
        return try self.allocator.dupe(u8, gen.getOutput());
    }

    /// Compile AST to executable file
    pub fn compileToExecutable(
        self: *Compiler,
        program: *const ast.Program,
        output_path: []const u8,
        type_checker: ?*TypeChecker,
        type_layouts: ?*const std.StringHashMap(TypeLayout),
        io: std.Io,
    ) !void {
        switch (self.target_config.target) {
            .native_x64_linux => try self.compileToNativeExecutable(program, output_path, type_checker, type_layouts, io),
            .templeos, .zealos => try self.compileToTempleOSBin(program, output_path, type_checker, type_layouts, io),
        }
    }

    /// Compile to native Linux x64 executable via GCC
    fn compileToNativeExecutable(
        self: *Compiler,
        program: *const ast.Program,
        output_path: []const u8,
        type_checker: ?*TypeChecker,
        type_layouts: ?*const std.StringHashMap(TypeLayout),
        io: std.Io,
    ) !void {
        // Generate assembly
        const asm_code = try self.compileToAssembly(program, type_checker, type_layouts);
        defer self.allocator.free(asm_code);

        // Write assembly to temporary file
        const asm_path = try std.fmt.allocPrint(self.allocator, "{s}.s", .{output_path});
        defer self.allocator.free(asm_path);

        const cwd = std.Io.Dir.cwd();
        const asm_file = try cwd.createFile(io, asm_path, .{});
        defer asm_file.close(io);
        try asm_file.writeStreamingAll(io, asm_code);

        // Use gcc to assemble and link (simpler than using as + ld directly)
        var child = try std.process.spawn(io, .{
            .argv = &[_][]const u8{ "gcc", "-o", output_path, asm_path, "-no-pie" },
        });

        const term = try child.wait(io);

        if (term != .exited or term.exited != 0) {
            std.debug.print("GCC compilation failed with exit code: {}\n", .{term});
            return error.CompilationFailed;
        }

        // Clean up intermediate files
        try cwd.deleteFile(io, asm_path);
    }

    /// Compile to TempleOS/ZealOS .BIN format
    fn compileToTempleOSBin(
        self: *Compiler,
        program: *const ast.Program,
        output_path: []const u8,
        type_checker: ?*TypeChecker,
        type_layouts: ?*const std.StringHashMap(TypeLayout),
        io: std.Io,
    ) !void {
        // Build IR from AST
        var builder = try ir_builder.IRBuilder.init(self.allocator, type_checker, type_layouts);
        defer builder.deinit();

        try builder.buildFromAST(program);
        const module = try builder.finish();
        var mod = module;
        defer mod.deinit();

        // Initialize TempleOS binary writer
        var bin_writer = try templeos_bin.TempleOSBinWriter.init(self.allocator);
        defer bin_writer.deinit();

        // Generate machine code
        var machine_gen = try x64_machine_code.X64MachineCodeGen.init(self.allocator, &bin_writer);
        defer machine_gen.deinit();

        try machine_gen.generateFromIR(&mod);

        // Write .BIN file
        try bin_writer.writeToBinFile(io, output_path);
    }

    pub fn deinit(self: *Compiler) void {
        _ = self;
    }
};
