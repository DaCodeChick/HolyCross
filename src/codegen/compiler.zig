const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const ir_builder = @import("ir_builder.zig");
const x64 = @import("x64.zig");
const ast = @import("../parser/ast.zig");
const type_checker_module = @import("../semantic/type_checker.zig");

const TypeChecker = type_checker_module.TypeChecker;

/// Compiler - orchestrates the compilation pipeline
pub const Compiler = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Compiler {
        return .{ .allocator = allocator };
    }

    /// Compile AST to x64 assembly string
    pub fn compileToAssembly(self: *Compiler, program: *const ast.Program, type_checker: ?*TypeChecker) ![]const u8 {
        // Build IR from AST
        var builder = try ir_builder.IRBuilder.init(self.allocator, type_checker);
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
    pub fn compileToExecutable(self: *Compiler, program: *const ast.Program, output_path: []const u8, type_checker: ?*TypeChecker) !void {
        // Generate assembly
        const asm_code = try self.compileToAssembly(program, type_checker);
        defer self.allocator.free(asm_code);

        // Write assembly to temporary file
        const asm_path = try std.fmt.allocPrint(self.allocator, "{s}.s", .{output_path});
        defer self.allocator.free(asm_path);

        const asm_file = try std.fs.cwd().createFile(asm_path, .{});
        defer asm_file.close();
        try asm_file.writeAll(asm_code);

        // Use gcc to assemble and link (simpler than using as + ld directly)
        const gcc_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "gcc", "-o", output_path, asm_path, "-no-pie" },
        });
        defer self.allocator.free(gcc_result.stdout);
        defer self.allocator.free(gcc_result.stderr);

        if (gcc_result.term.Exited != 0) {
            std.debug.print("GCC error:\n{s}\n", .{gcc_result.stderr});
            return error.CompilationFailed;
        }

        // Clean up intermediate files
        try std.fs.cwd().deleteFile(asm_path);
    }

    pub fn deinit(self: *Compiler) void {
        _ = self;
    }
};
