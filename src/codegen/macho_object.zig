//! Mach-O Object File Writer
//!
//! Generates Mach-O relocatable object files (.o) for macOS/Darwin x64.
//!
//! File structure:
//! - mach_header_64: Magic, CPU type, file type, load commands count
//! - Load Commands:
//!   - LC_SEGMENT_64: __TEXT segment (contains __text section for code)
//!   - LC_SEGMENT_64: __DATA segment (contains __data, __bss sections)
//!   - LC_SYMTAB: Symbol table
//! - Section data (__text, __data)
//! - Relocations
//! - Symbol table (nlist_64 entries)
//! - String table
//!
//! References:
//! - https://github.com/aidansteele/osx-abi-macho-file-format-reference
//! - /usr/include/mach-o/loader.h
//! - Zig's std/macho.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
const macho = std.macho;

/// Mach-O object file writer for x64 macOS
pub const MachoObjectWriter = struct {
    allocator: Allocator,
    text_code: std.ArrayList(u8),
    data_section: std.ArrayList(u8),
    bss_size: usize,
    symbols: std.ArrayList(Symbol),
    relocations: std.ArrayList(Relocation),
    string_table: std.ArrayList(u8),
    string_map: std.StringHashMap(u32), // Map string -> offset in string table

    pub const Symbol = struct {
        name: []const u8,
        section: SymbolSection,
        value: u64,
        is_external: bool,
    };

    pub const SymbolSection = enum(u8) {
        undefined = 0,  // External/undefined symbol
        text = 1,       // __TEXT,__text
        data = 2,       // __DATA,__data
        bss = 3,        // __DATA,__bss
    };

    pub const Relocation = struct {
        offset: u32,        // Offset in section
        symbol_index: u32,  // Index in symbol table
        pcrel: bool,        // PC-relative?
        length: u2,         // 0=byte, 1=word, 2=long, 3=quad
        is_extern: bool,    // External symbol?
        type: u4,           // Relocation type
    };

    pub fn init(allocator: Allocator) !MachoObjectWriter {
        var string_table = std.ArrayList(u8){ .items = &.{}, .capacity = 0 };
        // String table starts with a null byte
        try string_table.append(allocator, 0);

        return .{
            .allocator = allocator,
            .text_code = .{ .items = &.{}, .capacity = 0 },
            .data_section = .{ .items = &.{}, .capacity = 0 },
            .bss_size = 0,
            .symbols = .{ .items = &.{}, .capacity = 0 },
            .relocations = .{ .items = &.{}, .capacity = 0 },
            .string_table = string_table,
            .string_map = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *MachoObjectWriter) void {
        self.text_code.deinit(self.allocator);
        self.data_section.deinit(self.allocator);
        self.symbols.deinit(self.allocator);
        self.relocations.deinit(self.allocator);
        self.string_table.deinit(self.allocator);
        self.string_map.deinit();
    }

    /// Add code to the __text section
    pub fn appendCode(self: *MachoObjectWriter, code: []const u8) !void {
        try self.text_code.appendSlice(self.allocator, code);
    }

    pub fn appendData(self: *MachoObjectWriter, data: []const u8) !u64 {
        const offset = @as(u64, @intCast(self.data_section.items.len));
        try self.data_section.appendSlice(self.allocator, data);
        return offset;
    }

    /// Reserve space in __bss section
    pub fn addBss(self: *MachoObjectWriter, size: usize) !void {
        self.bss_size += size;
    }

    /// Add a symbol to the symbol table
    pub fn addSymbol(
        self: *MachoObjectWriter,
        name: []const u8,
        section: SymbolSection,
        value: u64,
        is_external: bool,
    ) !void {
        try self.symbols.append(self.allocator, .{
            .name = name,
            .section = section,
            .value = value,
            .is_external = is_external,
        });
    }

    /// Add a relocation entry
    pub fn addRelocation(
        self: *MachoObjectWriter,
        offset: u32,
        symbol_index: u32,
        pcrel: bool,
        length: u2,
        is_extern: bool,
        rel_type: u4,
    ) !void {
        try self.relocations.append(self.allocator, .{
            .offset = offset,
            .symbol_index = symbol_index,
            .pcrel = pcrel,
            .length = length,
            .is_extern = is_extern,
            .type = rel_type,
        });
    }

    /// Get or add string to string table, return offset
    fn getStringOffset(self: *MachoObjectWriter, str: []const u8) !u32 {
        if (self.string_map.get(str)) |offset| {
            return offset;
        }

        const offset = @as(u32, @intCast(self.string_table.items.len));
        try self.string_table.appendSlice(self.allocator, str);
        try self.string_table.append(self.allocator, 0); // Null terminator
        try self.string_map.put(str, offset);
        return offset;
    }

    /// Write Mach-O object file
    pub fn writeToFile(self: *MachoObjectWriter, io: std.Io, path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.createFile(io, path, .{});
        defer file.close(io);

        var write_buffer: [8192]u8 = undefined;
        var buffered_writer = file.writer(io, &write_buffer);
        defer buffered_writer.flush() catch {};
        
        // Track position manually since Zig 0.16 File doesn't have getPos()
        var current_pos: u32 = 0;

        // Calculate sizes and offsets
        const text_size = self.text_code.items.len;
        const data_size = self.data_section.items.len;
        const bss_size = self.bss_size;
        
        const text_align: u32 = 4; // 2^4 = 16 bytes
        const data_align: u32 = 3; // 2^3 = 8 bytes
        
        // Calculate load command sizes
        const segment_cmd_size = @sizeOf(macho.segment_command_64);
        const section_64_size = @sizeOf(macho.section_64);
        const symtab_cmd_size = @sizeOf(macho.symtab_command);
        
        // We'll have:
        // - 1 segment with 1 section (__TEXT with __text)
        // - 1 segment with 2 sections (__DATA with __data, __bss)
        // - 1 symtab command
        const text_segment_size = segment_cmd_size + section_64_size;
        const data_segment_size = segment_cmd_size + 2 * section_64_size;
        const load_cmds_size = text_segment_size + data_segment_size + symtab_cmd_size;
        
        // File offsets
        const header_size = @sizeOf(macho.mach_header_64);
        var file_offset: u32 = @intCast(header_size + load_cmds_size);
        
        // Align to 16 bytes
        file_offset = (file_offset + 15) & ~@as(u32, 15);
        
        const text_offset = file_offset;
        file_offset += @intCast(text_size);
        file_offset = (file_offset + 15) & ~@as(u32, 15);
        
        const data_offset = file_offset;
        file_offset += @intCast(data_size);
        file_offset = (file_offset + 15) & ~@as(u32, 15);
        
        const reloc_offset = file_offset;
        const reloc_size = self.relocations.items.len * @sizeOf(macho.relocation_info);
        file_offset += @intCast(reloc_size);
        
        const symtab_offset = file_offset;
        const symtab_size = self.symbols.items.len * @sizeOf(macho.nlist_64);
        file_offset += @intCast(symtab_size);
        
        const strtab_offset = file_offset;
        const strtab_size = self.string_table.items.len;

        // Write mach_header_64
        const header = macho.mach_header_64{
            .magic = macho.MH_MAGIC_64,
            .cputype = macho.CPU_TYPE_X86_64,
            .cpusubtype = macho.CPU_SUBTYPE_X86_64_ALL,
            .filetype = macho.MH_OBJECT,
            .ncmds = 3, // __TEXT segment, __DATA segment, LC_SYMTAB
            .sizeofcmds = @intCast(load_cmds_size),
            .flags = 0,
            .reserved = 0,
        };
        try buffered_writer.interface.writeStruct(header, .little);
        current_pos += @sizeOf(macho.mach_header_64);

        // Write __TEXT segment load command
        var text_segname = [_]u8{0} ** 16;
        @memcpy(text_segname[0.."__TEXT".len], "__TEXT");
        
        const text_segment = macho.segment_command_64{
            .cmd = .SEGMENT_64,
            .cmdsize = @intCast(text_segment_size),
            .segname = text_segname,
            .vmaddr = 0,
            .vmsize = text_size,
            .fileoff = text_offset,
            .filesize = text_size,
            .maxprot = .{ .READ = true, .WRITE = false, .EXEC = true },
            .initprot = .{ .READ = true, .WRITE = false, .EXEC = true },
            .nsects = 1,
            .flags = 0,
        };
        try buffered_writer.interface.writeStruct(text_segment, .little);
        current_pos += @sizeOf(macho.segment_command_64);

        // Write __text section
        var text_sectname = [_]u8{0} ** 16;
        @memcpy(text_sectname[0.."__text".len], "__text");
        
        const text_section = macho.section_64{
            .sectname = text_sectname,
            .segname = text_segname,
            .addr = 0,
            .size = text_size,
            .offset = text_offset,
            .@"align" = text_align,
            .reloff = @intCast(reloc_offset),
            .nreloc = @intCast(self.relocations.items.len),
            .flags = macho.S_REGULAR | macho.S_ATTR_PURE_INSTRUCTIONS | macho.S_ATTR_SOME_INSTRUCTIONS,
            .reserved1 = 0,
            .reserved2 = 0,
            .reserved3 = 0,
        };
        try buffered_writer.interface.writeStruct(text_section, .little);
        current_pos += @sizeOf(macho.section_64);

        // Write __DATA segment load command
        var data_segname = [_]u8{0} ** 16;
        @memcpy(data_segname[0.."__DATA".len], "__DATA");
        
        const data_vmsize = data_size + bss_size;
        const data_segment = macho.segment_command_64{
            .cmd = .SEGMENT_64,
            .cmdsize = @intCast(data_segment_size),
            .segname = data_segname,
            .vmaddr = 0,
            .vmsize = data_vmsize,
            .fileoff = data_offset,
            .filesize = data_size,
            .maxprot = .{ .READ = true, .WRITE = true, .EXEC = false },
            .initprot = .{ .READ = true, .WRITE = true, .EXEC = false },
            .nsects = 2,
            .flags = 0,
        };
        try buffered_writer.interface.writeStruct(data_segment, .little);
        current_pos += @sizeOf(macho.segment_command_64);

        // Write __data section
        var data_sectname = [_]u8{0} ** 16;
        @memcpy(data_sectname[0.."__data".len], "__data");
        
        const data_sect = macho.section_64{
            .sectname = data_sectname,
            .segname = data_segname,
            .addr = 0,
            .size = data_size,
            .offset = data_offset,
            .@"align" = data_align,
            .reloff = 0,
            .nreloc = 0,
            .flags = macho.S_REGULAR,
            .reserved1 = 0,
            .reserved2 = 0,
            .reserved3 = 0,
        };
        try buffered_writer.interface.writeStruct(data_sect, .little);
        current_pos += @sizeOf(macho.section_64);

        // Write __bss section
        var bss_sectname = [_]u8{0} ** 16;
        @memcpy(bss_sectname[0.."__bss".len], "__bss");
        
        const bss_sect = macho.section_64{
            .sectname = bss_sectname,
            .segname = data_segname,
            .addr = data_size,
            .size = bss_size,
            .offset = 0,
            .@"align" = data_align,
            .reloff = 0,
            .nreloc = 0,
            .flags = macho.S_ZEROFILL,
            .reserved1 = 0,
            .reserved2 = 0,
            .reserved3 = 0,
        };
        try buffered_writer.interface.writeStruct(bss_sect, .little);
        current_pos += @sizeOf(macho.section_64);

        // Write LC_SYMTAB command
        const symtab_cmd = macho.symtab_command{
            .cmd = .SYMTAB,
            .cmdsize = @intCast(symtab_cmd_size),
            .symoff = @intCast(symtab_offset),
            .nsyms = @intCast(self.symbols.items.len),
            .stroff = @intCast(strtab_offset),
            .strsize = @intCast(strtab_size),
        };
        try buffered_writer.interface.writeStruct(symtab_cmd, .little);
        current_pos += @sizeOf(macho.symtab_command);

        // Pad to text section offset
        while (current_pos < text_offset) {
            try buffered_writer.interface.writeByte(0);
            current_pos += 1;
        }

        // Write __text section data
        try buffered_writer.interface.writeAll(self.text_code.items);
        current_pos += @intCast(self.text_code.items.len);

        // Pad to data section offset
        while (current_pos < data_offset) {
            try buffered_writer.interface.writeByte(0);
            current_pos += 1;
        }

        // Write __data section data
        try buffered_writer.interface.writeAll(self.data_section.items);
        current_pos += @intCast(self.data_section.items.len);

        // Pad to relocation offset
        while (current_pos < reloc_offset) {
            try buffered_writer.interface.writeByte(0);
            current_pos += 1;
        }

        // Write relocations
        for (self.relocations.items) |reloc| {
            const reloc_info = macho.relocation_info{
                .r_address = @intCast(reloc.offset),
                .r_symbolnum = @intCast(reloc.symbol_index),
                .r_pcrel = @intFromBool(reloc.pcrel),
                .r_length = reloc.length,
                .r_extern = @intFromBool(reloc.is_extern),
                .r_type = reloc.type,
            };
            
            // Pack relocation info into two 32-bit values
            const r_address: i32 = reloc_info.r_address;
            try buffered_writer.interface.writeInt(i32, r_address, .little);
            
            // Pack the second word: symbolnum(24) | pcrel(1) | length(2) | extern(1) | type(4)
            var packed_bits: u32 = 0;
            packed_bits |= @as(u32, reloc_info.r_symbolnum) & 0xFFFFFF;
            if (reloc_info.r_pcrel != 0) packed_bits |= 0x01000000;
            packed_bits |= (@as(u32, reloc_info.r_length) & 0x3) << 25;
            if (reloc_info.r_extern != 0) packed_bits |= 0x08000000;
            packed_bits |= (@as(u32, reloc_info.r_type) & 0xF) << 28;
            try buffered_writer.interface.writeInt(u32, packed_bits, .little);
        }

        // Write symbol table
        for (self.symbols.items) |sym| {
            const str_offset = try self.getStringOffset(sym.name);
            
            const n_sect: u8 = @intFromEnum(sym.section);
            
            const nlist = macho.nlist_64{
                .n_strx = str_offset,
                .n_type = .{ .bits = .{
                    .ext = sym.is_external,
                    .type = if (sym.section == .undefined) .undf else .sect,
                    .pext = false,
                    .is_stab = 0,
                } },
                .n_sect = n_sect,
                .n_desc = .{
                    ._pad0 = 0,
                    .arm_thumb_def = false,
                    .referenced_dynamically = false,
                    .discarded_or_no_dead_strip = false,
                    .weak_ref = false,
                    .weak_def_or_ref_to_weak = false,
                    .symbol_resolver = false,
                    .alt_entry = false,
                    ._pad2 = 0,
                },
                .n_value = sym.value,
            };
            
            try buffered_writer.interface.writeStruct(nlist, .little);
        }

        // Write string table
        try buffered_writer.interface.writeAll(self.string_table.items);
    }
};
