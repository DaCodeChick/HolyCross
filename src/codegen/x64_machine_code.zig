const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const templeos_bin = @import("templeos_bin.zig");

/// x64 Machine Code Generator for TempleOS/ZealOS .BIN format
/// Generates raw machine code instead of assembly text
pub const X64MachineCodeGen = struct {
    allocator: Allocator,
    bin_writer: *templeos_bin.TempleOSBinWriter,
    /// Label to offset mapping
    labels: std.StringHashMap(u32),
    /// Unresolved label references (offset in code, label name, is_relative)
    unresolved_refs: std.ArrayList(LabelRef),
    
    const LabelRef = struct {
        offset: u32,
        label: []const u8,
        is_relative: bool, // true for relative jumps, false for absolute addresses
    };

    pub fn init(allocator: Allocator, bin_writer: *templeos_bin.TempleOSBinWriter) !X64MachineCodeGen {
        const empty_refs = try allocator.alloc(LabelRef, 0);
        return .{
            .allocator = allocator,
            .bin_writer = bin_writer,
            .labels = std.StringHashMap(u32).init(allocator),
            .unresolved_refs = std.ArrayList(LabelRef).fromOwnedSlice(empty_refs),
        };
    }

    pub fn deinit(self: *X64MachineCodeGen) void {
        var label_iter = self.labels.keyIterator();
        while (label_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.labels.deinit();
        
        for (self.unresolved_refs.items) |ref| {
            self.allocator.free(ref.label);
        }
        self.unresolved_refs.deinit(self.allocator);
    }

    /// Generate machine code from IR module
    pub fn generateFromIR(self: *X64MachineCodeGen, module: *const ir.Module) !void {
        // For now, just generate a minimal stub that returns 42
        // TODO: Actually translate IR to machine code
        
        // Find main function
        var main_func: ?*const ir.Function = null;
        for (module.functions.items) |*func| {
            if (std.mem.eql(u8, func.name, "main")) {
                main_func = func;
                break;
            }
        }

        if (main_func == null) {
            return error.NoMainFunction;
        }

        // Emit minimal function prologue
        // push rbp
        try self.emitByte(0x55);
        
        // mov rbp, rsp
        try self.emitBytes(&[_]u8{ 0x48, 0x89, 0xE5 });
        
        // mov eax, 42  (for testing)
        try self.emitBytes(&[_]u8{ 0xB8, 0x2A, 0x00, 0x00, 0x00 });
        
        // pop rbp
        try self.emitByte(0x5D);
        
        // ret
        try self.emitByte(0xC3);

        // Set entry point to start of code (offset 0)
        try self.bin_writer.setEntryPoint(0);
    }

    fn emitByte(self: *X64MachineCodeGen, byte: u8) !void {
        try self.bin_writer.appendCode(&[_]u8{byte});
    }

    fn emitBytes(self: *X64MachineCodeGen, bytes: []const u8) !void {
        try self.bin_writer.appendCode(bytes);
    }

    /// Define a label at current position
    fn defineLabel(self: *X64MachineCodeGen, name: []const u8) !void {
        const offset = self.bin_writer.getCurrentOffset();
        const owned_name = try self.allocator.dupe(u8, name);
        try self.labels.put(owned_name, offset);
    }

    /// Add an unresolved reference to a label
    fn addLabelRef(self: *X64MachineCodeGen, label: []const u8, is_relative: bool) !void {
        const offset = self.bin_writer.getCurrentOffset();
        const owned_label = try self.allocator.dupe(u8, label);
        try self.unresolved_refs.append(.{
            .offset = offset,
            .label = owned_label,
            .is_relative = is_relative,
        });
    }

    /// Resolve all label references and add relocations to patch table
    fn resolveLabels(self: *X64MachineCodeGen) !void {
        for (self.unresolved_refs.items) |ref| {
            _ = self.labels.get(ref.label) orelse {
                std.debug.print("Error: Undefined label '{s}'\n", .{ref.label});
                return error.UndefinedLabel;
            };

            if (ref.is_relative) {
                // For relative jumps, calculate displacement
                // (handled during code emission)
            } else {
                // For absolute addresses, add to patch table
                try self.bin_writer.addAbsoluteRelocation(ref.offset);
            }
        }
    }
};
