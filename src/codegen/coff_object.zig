const std = @import("std");
const Allocator = std.mem.Allocator;

/// COFF Object File Writer for Windows x64
/// Generates .obj files compatible with Microsoft link.exe and MinGW ld
pub const COFFObjectWriter = struct {
    allocator: Allocator,
    
    // Machine code and data
    text_section: std.ArrayList(u8),
    data_section: std.ArrayList(u8),
    rdata_section: std.ArrayList(u8),
    bss_size: u32,
    
    // Symbols
    symbols: std.ArrayList(Symbol),
    string_table: std.ArrayList(u8),
    
    // Relocations
    relocations: std.ArrayList(Relocation),
    
    pub const Symbol = struct {
        name: []const u8,
        value: u32,
        section_number: i16,  // 1-based; -1=absolute, 0=undefined
        type: u16,            // 0x20 = function, 0x00 = not a function
        storage_class: u8,    // 2=external, 3=static, 103=section
        aux_count: u8,
    };
    
    pub const Relocation = struct {
        virtual_address: u32,   // Offset in section
        symbol_index: u32,      // Index into symbol table
        type: RelocationType,
    };
    
    pub const RelocationType = enum(u16) {
        ADDR64 = 0x0001,    // 64-bit absolute address
        ADDR32 = 0x0002,    // 32-bit absolute address
        ADDR32NB = 0x0003,  // 32-bit address without image base
        REL32 = 0x0004,     // 32-bit relative to instruction end
        REL32_1 = 0x0005,   // 32-bit relative to instruction end - 1
        REL32_2 = 0x0006,   // 32-bit relative to instruction end - 2
        REL32_3 = 0x0007,   // 32-bit relative to instruction end - 3
        REL32_4 = 0x0008,   // 32-bit relative to instruction end - 4
        REL32_5 = 0x0009,   // 32-bit relative to instruction end - 5
        SECTION = 0x000A,   // Section index
        SECREL = 0x000B,    // 32-bit offset from section start
        SECREL7 = 0x000C,   // 7-bit unsigned offset from section base
        TOKEN = 0x000D,     // CLR token
        SREL32 = 0x000E,    // 32-bit signed span-dependent value
        PAIR = 0x000F,      // Pair (used with other reloc types)
        SSPAN32 = 0x0010,   // 32-bit signed span-dependent value
    };
    
    pub fn init(allocator: Allocator) !COFFObjectWriter {
        const empty_text = try allocator.alloc(u8, 0);
        const empty_data = try allocator.alloc(u8, 0);
        const empty_rdata = try allocator.alloc(u8, 0);
        const empty_symbols = try allocator.alloc(Symbol, 0);
        const empty_string_table = try allocator.alloc(u8, 0);
        const empty_relocs = try allocator.alloc(Relocation, 0);
        
        // String table starts with 4-byte size (will be filled later)
        var string_table = std.ArrayList(u8).fromOwnedSlice(empty_string_table);
        try string_table.appendSlice(allocator, &[4]u8{4, 0, 0, 0}); // Initial size
        
        return .{
            .allocator = allocator,
            .text_section = std.ArrayList(u8).fromOwnedSlice(empty_text),
            .data_section = std.ArrayList(u8).fromOwnedSlice(empty_data),
            .rdata_section = std.ArrayList(u8).fromOwnedSlice(empty_rdata),
            .bss_size = 0,
            .symbols = std.ArrayList(Symbol).fromOwnedSlice(empty_symbols),
            .string_table = string_table,
            .relocations = std.ArrayList(Relocation).fromOwnedSlice(empty_relocs),
        };
    }
    
    pub fn deinit(self: *COFFObjectWriter) void {
        self.text_section.deinit(self.allocator);
        self.data_section.deinit(self.allocator);
        self.rdata_section.deinit(self.allocator);
        self.symbols.deinit(self.allocator);
        self.string_table.deinit(self.allocator);
        self.relocations.deinit(self.allocator);
    }
    
    /// Add machine code to .text section
    pub fn addCode(self: *COFFObjectWriter, code: []const u8) !void {
        try self.text_section.appendSlice(self.allocator, code);
    }
    
    /// Compatibility wrapper for appendCode (used by CodeBuffer)
    pub fn appendCode(self: *COFFObjectWriter, code: []const u8) !void {
        try self.addCode(code);
    }
    
    /// Add initialized data to .data section
    pub fn addData(self: *COFFObjectWriter, data: []const u8) !void {
        try self.data_section.appendSlice(self.allocator, data);
    }
    
    /// Compatibility wrapper for appendData (used by CodeBuffer)
    pub fn appendData(self: *COFFObjectWriter, data: []const u8) !u64 {
        const offset = self.data_section.items.len;
        try self.addData(data);
        return @intCast(offset);
    }
    
    /// Add read-only data to .rdata section (string literals, constants)
    pub fn addReadOnlyData(self: *COFFObjectWriter, data: []const u8) !void {
        try self.rdata_section.appendSlice(self.allocator, data);
    }
    
    /// Reserve space in .bss section (uninitialized data)
    pub fn addBSS(self: *COFFObjectWriter, size: u32) !void {
        self.bss_size += size;
    }
    
    /// Add a symbol to the symbol table
    pub fn addSymbol(self: *COFFObjectWriter, symbol: Symbol) !u32 {
        const index = @as(u32, @intCast(self.symbols.items.len));
        try self.symbols.append(self.allocator, symbol);
        return index;
    }
    
    /// Add a relocation entry
    pub fn addRelocation(self: *COFFObjectWriter, reloc: Relocation) !void {
        try self.relocations.append(self.allocator, reloc);
    }
    
    /// Add a string to the string table and return its offset
    fn addStringToTable(self: *COFFObjectWriter, str: []const u8) !u32 {
        const offset = @as(u32, @intCast(self.string_table.items.len));
        try self.string_table.appendSlice(self.allocator, str);
        try self.string_table.append(self.allocator, 0); // Null terminator
        return offset;
    }
    
    /// Write the complete COFF object file
    pub fn writeToFile(self: *COFFObjectWriter, io: std.Io, path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.createFile(io, path, .{});
        defer file.close(io);
        
        var write_buffer: [8192]u8 = undefined;
        var buffered_writer = file.writer(io, &write_buffer);
        defer buffered_writer.flush() catch {};
        
        try self.write(&buffered_writer.interface);
    }
    
    /// Write COFF object to a Writer interface
    pub fn write(self: *COFFObjectWriter, writer: *std.Io.Writer) !void {
        // Calculate section count (only include sections with content)
        var section_count: u16 = 0;
        if (self.text_section.items.len > 0) section_count += 1;
        if (self.data_section.items.len > 0) section_count += 1;
        if (self.rdata_section.items.len > 0) section_count += 1;
        if (self.bss_size > 0) section_count += 1;
        
        // Add section symbols
        var symbol_count = @as(u32, @intCast(self.symbols.items.len));
        if (self.text_section.items.len > 0) symbol_count += 1;
        if (self.data_section.items.len > 0) symbol_count += 1;
        if (self.rdata_section.items.len > 0) symbol_count += 1;
        if (self.bss_size > 0) symbol_count += 1;
        
        // Update string table size
        std.mem.writeInt(u32, self.string_table.items[0..4], @intCast(self.string_table.items.len), .little);
        
        // Calculate offsets
        const header_size: u32 = 20;
        const section_header_size: u32 = 40;
        
        const offset: u32 = header_size + (section_count * section_header_size);
        
        const text_offset = offset;
        const data_offset = text_offset + @as(u32, @intCast(self.text_section.items.len));
        const rdata_offset = data_offset + @as(u32, @intCast(self.data_section.items.len));
        const reloc_offset = rdata_offset + @as(u32, @intCast(self.rdata_section.items.len));
        
        // Calculate symbol table offset (after relocations)
        const reloc_size = @as(u32, @intCast(self.relocations.items.len)) * 10; // Relocation entry = 10 bytes
        const symbol_table_offset = reloc_offset + reloc_size;
        
        // Write COFF header
        try self.writeCOFFHeader(writer, section_count, symbol_table_offset, symbol_count);
        
        // Write section headers
        var section_number: i16 = 1;
        if (self.text_section.items.len > 0) {
            try self.writeSectionHeader(writer, ".text", @intCast(self.text_section.items.len), 
                text_offset, @intCast(self.relocations.items.len), reloc_offset, 
                0x60000020); // CODE | EXECUTE | READ
            section_number += 1;
        }
        
        if (self.data_section.items.len > 0) {
            try self.writeSectionHeader(writer, ".data", @intCast(self.data_section.items.len), 
                data_offset, 0, 0, 
                0xC0000040); // INITIALIZED_DATA | READ | WRITE
            section_number += 1;
        }
        
        if (self.rdata_section.items.len > 0) {
            try self.writeSectionHeader(writer, ".rdata", @intCast(self.rdata_section.items.len), 
                rdata_offset, 0, 0, 
                0x40000040); // INITIALIZED_DATA | READ
            section_number += 1;
        }
        
        if (self.bss_size > 0) {
            try self.writeSectionHeader(writer, ".bss", self.bss_size, 
                0, 0, 0, 
                0xC0000080); // UNINITIALIZED_DATA | READ | WRITE
        }
        
        // Write section data
        if (self.text_section.items.len > 0) {
            try writer.writeAll(self.text_section.items);
        }
        if (self.data_section.items.len > 0) {
            try writer.writeAll(self.data_section.items);
        }
        if (self.rdata_section.items.len > 0) {
            try writer.writeAll(self.rdata_section.items);
        }
        
        // Write relocations
        for (self.relocations.items) |reloc| {
            try writer.writeInt(u32, reloc.virtual_address, .little);
            try writer.writeInt(u32, reloc.symbol_index, .little);
            try writer.writeInt(u16, @intFromEnum(reloc.type), .little);
        }
        
        // Write section symbols first
        section_number = 1;
        if (self.text_section.items.len > 0) {
            try self.writeSymbolEntry(writer, ".text", 0, section_number, 0, 103, 0);
            section_number += 1;
        }
        if (self.data_section.items.len > 0) {
            try self.writeSymbolEntry(writer, ".data", 0, section_number, 0, 103, 0);
            section_number += 1;
        }
        if (self.rdata_section.items.len > 0) {
            try self.writeSymbolEntry(writer, ".rdata", 0, section_number, 0, 103, 0);
            section_number += 1;
        }
        if (self.bss_size > 0) {
            try self.writeSymbolEntry(writer, ".bss", 0, section_number, 0, 103, 0);
        }
        
        // Write user symbols
        for (self.symbols.items) |symbol| {
            try self.writeSymbolEntry(writer, symbol.name, symbol.value, symbol.section_number, 
                symbol.type, symbol.storage_class, symbol.aux_count);
        }
        
        // Write string table
        try writer.writeAll(self.string_table.items);
    }
    
    fn writeCOFFHeader(self: *COFFObjectWriter, writer: *std.Io.Writer, section_count: u16, 
                       symbol_table_offset: u32, symbol_count: u32) !void {
        _ = self;
        try writer.writeInt(u16, 0x8664, .little);  // Machine: AMD64
        try writer.writeInt(u16, section_count, .little);
        // For now, just use 0 for timestamp (deterministic builds)
        try writer.writeInt(u32, 0, .little);  // Timestamp
        try writer.writeInt(u32, symbol_table_offset, .little);
        try writer.writeInt(u32, symbol_count, .little);
        try writer.writeInt(u16, 0, .little);  // Size of optional header (0 for objects)
        try writer.writeInt(u16, 0, .little);  // Characteristics
    }
    
    fn writeSectionHeader(self: *COFFObjectWriter, writer: *std.Io.Writer, name: []const u8, 
                          size: u32, offset: u32, num_relocs: u16, reloc_offset: u32, 
                          characteristics: u32) !void {
        _ = self;
        // Write name (8 bytes, padded with zeros or string table offset)
        var name_bytes: [8]u8 = [_]u8{0} ** 8;
        if (name.len <= 8) {
            @memcpy(name_bytes[0..name.len], name);
        } else {
            // TODO: Handle long names via string table reference
            @memcpy(name_bytes[0..8], name[0..8]);
        }
        try writer.writeAll(&name_bytes);
        
        try writer.writeInt(u32, 0, .little);  // Virtual size (0 for objects)
        try writer.writeInt(u32, 0, .little);  // Virtual address (0 for objects)
        try writer.writeInt(u32, size, .little);
        try writer.writeInt(u32, offset, .little);
        try writer.writeInt(u32, reloc_offset, .little);
        try writer.writeInt(u32, 0, .little);  // Line numbers offset (0)
        try writer.writeInt(u16, num_relocs, .little);
        try writer.writeInt(u16, 0, .little);  // Line numbers count (0)
        try writer.writeInt(u32, characteristics, .little);
    }
    
    fn writeSymbolEntry(self: *COFFObjectWriter, writer: *std.Io.Writer, name: []const u8, 
                        value: u32, section_number: i16, symbol_type: u16, 
                        storage_class: u8, aux_count: u8) !void {
        // Write name (8 bytes, or string table offset)
        var name_bytes: [8]u8 = [_]u8{0} ** 8;
        if (name.len <= 8) {
            @memcpy(name_bytes[0..name.len], name);
            try writer.writeAll(&name_bytes);
        } else {
            // Name is in string table: first 4 bytes = 0, next 4 = offset
            const offset = try self.addStringToTable(name);
            try writer.writeInt(u32, 0, .little);
            try writer.writeInt(u32, offset, .little);
        }
        
        try writer.writeInt(u32, value, .little);
        try writer.writeInt(i16, section_number, .little);
        try writer.writeInt(u16, symbol_type, .little);
        try writer.writeInt(u8, storage_class, .little);
        try writer.writeInt(u8, aux_count, .little);
    }
};
