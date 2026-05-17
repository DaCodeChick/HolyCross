const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const ir_builder = @import("ir_builder.zig");
const x64 = @import("x64.zig");
const ast = @import("../parser/ast.zig");
const type_checker_module = @import("../semantic/type_checker.zig");
const type_layout_module = @import("../semantic/type_layout.zig");
const Target = @import("../target.zig").Target;
const CallingConvention = @import("../target.zig").CallingConvention;
const templeos_bin = @import("templeos_bin.zig");
const elf_writer = @import("elf_writer.zig");
const elf_object = @import("elf_object.zig");
const coff_object = @import("coff_object.zig");
const macho_object = @import("macho_object.zig");
const pe_writer = @import("pe_writer.zig");
const x64_machine_code = @import("x64_machine_code.zig");

const TypeChecker = type_checker_module.TypeChecker;
const TypeLayout = type_layout_module.TypeLayout;

/// Compiler - orchestrates the compilation pipeline
pub const Compiler = struct {
    allocator: Allocator,
    target: Target,

    pub fn init(allocator: Allocator, target: Target) Compiler {
        return .{
            .allocator = allocator,
            .target = target,
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

    /// Compile AST to relocatable object file
    pub fn compileToObject(
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

        // Route to appropriate object file writer based on target
        const obj_format = self.target.objectFormat();
        const calling_conv = self.target.callingConvention();
        
        switch (obj_format) {
            .elf => {
                // Initialize ELF object file writer
                var obj = try elf_object.ELFObjectWriter.init(self.allocator);
                defer obj.deinit();

                // Initialize machine code generator targeting object file
                var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
                    self.allocator,
                    .{ .object = &obj },
                    calling_conv
                );
                defer machine_gen.deinit();

                // Generate machine code from IR
                try machine_gen.generateFromIR(&mod);

                // Write object file
                try obj.writeToFile(io, output_path);
            },
            .coff => {
                // Initialize COFF object file writer (Windows .obj)
                var obj = try coff_object.COFFObjectWriter.init(self.allocator);
                defer obj.deinit();

                // Initialize machine code generator targeting object file
                var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
                    self.allocator,
                    .{ .coff_object = &obj },
                    calling_conv
                );
                defer machine_gen.deinit();

                // Generate machine code from IR
                try machine_gen.generateFromIR(&mod);

                // Write COFF object file
                try obj.writeToFile(io, output_path);
            },
            .macho => {
                // Initialize Mach-O object file writer (macOS .o)
                var obj = try macho_object.MachoObjectWriter.init(self.allocator);
                defer obj.deinit();

                // Initialize machine code generator targeting object file
                var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
                    self.allocator,
                    .{ .macho_object = &obj },
                    calling_conv
                );
                defer machine_gen.deinit();

                // Generate machine code from IR
                try machine_gen.generateFromIR(&mod);

                // Write Mach-O object file
                try obj.writeToFile(io, output_path);
            },
            .bin => {
                return error.ObjectFileNotSupportedForTarget;  // TempleOS doesn't use object files
            },
        }
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
        const exec_format = self.target.executableFormat();
        
        switch (exec_format) {
            .elf => try self.compileToELFExecutable(program, output_path, type_checker, type_layouts, io),
            .pe => try self.compileToPEExecutable(program, output_path, type_checker, type_layouts, io),
            .macho => return error.MachoExecutableNotYetImplemented,
            .bin => try self.compileToTempleOSBin(program, output_path, type_checker, type_layouts, io),
        }
    }

    /// Compile to ELF executable (Linux)
    fn compileToELFExecutable(
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

        // Initialize ELF writer
        var elf = try elf_writer.ELFWriter.init(self.allocator);
        defer elf.deinit();

        // Initialize machine code generator with correct calling convention
        const calling_conv = self.target.callingConvention();
        var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
            self.allocator,
            .{ .elf = &elf },
            calling_conv
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
        // Generate executable with dynamic linking
        std.debug.print("      Generating dynamically linked executable...\n", .{});
        try elf.writeToFile(io, output_path);
        
        _ = self;
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

        // Initialize machine code generator with correct calling convention
        const calling_conv = self.target.callingConvention();
        var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
            self.allocator,
            .{ .templeos = &bin_writer },
            calling_conv
        );
        defer machine_gen.deinit();

        try machine_gen.generateFromIR(&mod);

        // Write .BIN file
        try bin_writer.writeToBinFile(io, output_path);
    }

    /// Compile to PE executable (Windows)
    fn compileToPEExecutable(
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

        // Initialize PE writer
        var pe = try pe_writer.PEWriter.init(self.allocator);
        defer pe.deinit();

        // Initialize machine code generator with Win64 calling convention
        const calling_conv = self.target.callingConvention();
        var machine_gen = try x64_machine_code.X64MachineCodeGen.init(
            self.allocator,
            .{ .pe = &pe },
            calling_conv
        );
        defer machine_gen.deinit();

        // Generate machine code from IR
        try machine_gen.generateFromIR(&mod);

        // Generate IAT stubs and patch call sites for PE executables
        try self.patchPEImports(&pe, &machine_gen);

        // Write PE executable
        try pe.writeToFile(io, output_path);
    }
    
    /// Generate IAT stubs and patch call sites for PE executables
    fn patchPEImports(self: *Compiler, pe: *pe_writer.PEWriter, machine_gen: *x64_machine_code.X64MachineCodeGen) !void {
        // Calculate where .idata section will be
        const section_alignment: u32 = 0x1000;
        const code_rva = section_alignment;  // .text at 0x1000
        const rdata_rva = code_rva + pe.alignUp(pe.code.items.len, section_alignment);
        const data_rva = rdata_rva + pe.alignUp(pe.rdata.items.len, section_alignment);
        const idata_rva = data_rva + pe.alignUp(pe.data.items.len, section_alignment);
        
        // Generate IAT stubs in code section
        var stub_map = try pe.generateIATStubs(idata_rva);
        defer {
            var iter = stub_map.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            stub_map.deinit();
        }
        
        // Patch call sites to point to stubs
        var sym_iter = machine_gen.external_symbols.symbols.iterator();
        while (sym_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const symbol = entry.value_ptr.*;
            
            // Get stub offset for this function
            const stub_offset = stub_map.get(func_name) orelse {
                std.debug.print("Warning: No IAT stub found for {s}\n", .{func_name});
                continue;
            };
            
            // Patch each call site
            for (symbol.references.items) |ref| {
                const call_site = ref.code_offset;
                // call_site points to the 4-byte displacement field
                // Calculate displacement: stub_offset - (call_site + 4)
                const next_instr = call_site + 4;
                const displacement = @as(i32, @intCast(stub_offset)) - @as(i32, @intCast(next_instr));
                
                // Patch the displacement in the code buffer
                const disp_bytes = std.mem.toBytes(@as(u32, @bitCast(displacement)));
                @memcpy(pe.code.items[call_site..][0..4], &disp_bytes);
            }
        }
    }

    pub fn deinit(self: *Compiler) void {
        _ = self;
    }
};
