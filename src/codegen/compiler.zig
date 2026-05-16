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
const elf_writer = @import("elf_writer.zig");
const elf_object = @import("elf_object.zig");
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
        var builder = try ir_builder.IRBuilder.init(self.allocator, self.target_config, type_checker, type_layouts);
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

    /// Compile AST to relocatable object file
    pub fn compileToObject(
        self: *Compiler,
        program: *const ast.Program,
        output_path: []const u8,
        type_checker: ?*TypeChecker,
        type_layouts: ?*const std.StringHashMap(TypeLayout),
        io: std.Io,
    ) !void {
        // Only support native x64 Linux for now
        if (self.target_config.target != .native_x64_linux) {
            return error.ObjectFileNotSupportedForTarget;
        }

        // Build IR from AST
        var builder = try ir_builder.IRBuilder.init(self.allocator, self.target_config, type_checker, type_layouts);
        defer builder.deinit();

        try builder.buildFromAST(program);
        const module = try builder.finish();
        var mod = module;
        defer mod.deinit();

        // Initialize object file writer
        var obj = try elf_object.ELFObjectWriter.init(self.allocator);
        defer obj.deinit();

        // Initialize machine code generator targeting object file
        var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
            self.allocator,
            .{ .object = &obj }
        );
        defer machine_gen.deinit();

        // Generate machine code from IR
        try machine_gen.generateFromIR(&mod);

        // Write object file
        try obj.writeToFile(io, output_path);
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

    /// Compile to native Linux x64 executable using machine code generator
    fn compileToNativeExecutable(
        self: *Compiler,
        program: *const ast.Program,
        output_path: []const u8,
        type_checker: ?*TypeChecker,
        type_layouts: ?*const std.StringHashMap(TypeLayout),
        io: std.Io,
    ) !void {
        // Build IR from AST
        var builder = try ir_builder.IRBuilder.init(self.allocator, self.target_config, type_checker, type_layouts);
        defer builder.deinit();

        try builder.buildFromAST(program);
        const module = try builder.finish();
        var mod = module;
        defer mod.deinit();

        // Initialize ELF writer
        var elf = try elf_writer.ELFWriter.init(self.allocator);
        defer elf.deinit();

        // Initialize machine code generator
        var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
            self.allocator,
            .{ .elf = &elf }
        );
        defer machine_gen.deinit();

        // Generate machine code from IR
        try machine_gen.generateFromIR(&mod);

        // Check if we have extern symbols
        if (elf.extern_symbols.items.len > 0) {
            // Generate object file and link with gcc
            std.debug.print("      Detected {} extern symbol(s), linking with libc...\n", .{elf.extern_symbols.items.len});
            try self.compileAndLinkWithLibc(&elf, output_path, io);
        } else {
            // Write ELF executable directly
            try elf.writeToFile(io, output_path);
        }
    }
    
    fn compileAndLinkWithLibc(
        self: *Compiler,
        elf: *elf_writer.ELFWriter,
        output_path: []const u8,
        io: std.Io,
    ) !void {
        // Generate object file with relocations, then link with hcl
        std.debug.print("      Generating object file with extern relocations...\n", .{});
        
        const obj_path = "/tmp/holycross_temp.o";
        
        // We need to convert our ELF executable writer data to object format
        // For now, use a simpler approach: generate the object file separately
        // TODO: Refactor to avoid duplication
        
        std.debug.print("\n", .{});
        std.debug.print("Extern function linking requires object file generation.\n", .{});
        std.debug.print("Extern symbols detected ({}):\n", .{elf.extern_symbols.items.len});
        for (elf.extern_symbols.items) |sym| {
            std.debug.print("  - {s} at offset 0x{x}\n", .{sym.name, sym.call_site_offset});
        }
        std.debug.print("\n", .{});
        std.debug.print("To complete linking:\n", .{});
        std.debug.print("  1. Compile to object file: hcc input.hc -c -o output.o\n", .{});
        std.debug.print("  2. Link with hcl: hcl output.o -lc -o executable\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Full implementation coming soon!\n", .{});
        
        _ = self;
        _ = obj_path;
        _ = output_path;
        _ = io;
        
        return error.ExternLinkingNotImplemented;
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
        var builder = try ir_builder.IRBuilder.init(self.allocator, self.target_config, type_checker, type_layouts);
        defer builder.deinit();

        try builder.buildFromAST(program);
        const module = try builder.finish();
        var mod = module;
        defer mod.deinit();

        // Initialize TempleOS binary writer
        var bin_writer = try templeos_bin.TempleOSBinWriter.init(self.allocator);
        defer bin_writer.deinit();

        // Initialize machine code generator
        var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
            self.allocator,
            .{ .templeos = &bin_writer }
        );
        defer machine_gen.deinit();

        try machine_gen.generateFromIR(&mod);

        // Write .BIN file
        try bin_writer.writeToBinFile(io, output_path);
    }

    pub fn deinit(self: *Compiler) void {
        _ = self;
    }
};
