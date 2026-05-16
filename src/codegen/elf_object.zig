const std = @import("std");
const Allocator = std.mem.Allocator;

/// ELF64 relocatable object file (.o) writer
/// Generates ELF object files suitable for linking with ld
pub const ELFObjectWriter = struct {
    allocator: Allocator,
    code: std.ArrayList(u8),
    data: std.ArrayList(u8),
    symbols: std.ArrayList(Symbol),
    relocations: std.ArrayList(Relocation),
    
    pub const Symbol = struct {
        name: []const u8,
        value: u64,
        size: u64,
        section: Section,
        binding: Binding,
        type: SymbolType,
        
        pub const Section = enum(u16) {
            undefined = 0,
            text = 1,
            data = 2,
            absolute = 0xFFF1,
        };
        
        pub const Binding = enum(u8) {
            local = 0,
            global = 1,
            weak = 2,
        };
        
        pub const SymbolType = enum(u8) {
            notype = 0,
            object = 1,
            func = 2,
            section = 3,
            file = 4,
        };
    };
    
    pub const Relocation = struct {
        offset: u64,
        symbol_index: u32,
        type: RelocationType,
        addend: i64,
        
        pub const RelocationType = enum(u32) {
            R_X86_64_NONE = 0,
            R_X86_64_64 = 1,        // Direct 64-bit
            R_X86_64_PC32 = 2,      // PC-relative 32-bit signed
            R_X86_64_32 = 10,       // Direct 32-bit zero-extend
            R_X86_64_32S = 11,      // Direct 32-bit sign-extend
            R_X86_64_PLT32 = 4,     // 32-bit PLT address
        };
    };
    
    pub fn init(allocator: Allocator) !ELFObjectWriter {
        const empty_code = try allocator.alloc(u8, 0);
        const empty_data = try allocator.alloc(u8, 0);
        const empty_symbols = try allocator.alloc(Symbol, 0);
        const empty_relocs = try allocator.alloc(Relocation, 0);
        
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).fromOwnedSlice(empty_code),
            .data = std.ArrayList(u8).fromOwnedSlice(empty_data),
            .symbols = std.ArrayList(Symbol).fromOwnedSlice(empty_symbols),
            .relocations = std.ArrayList(Relocation).fromOwnedSlice(empty_relocs),
        };
    }
    
    pub fn deinit(self: *ELFObjectWriter) void {
        self.code.deinit(self.allocator);
        self.data.deinit(self.allocator);
        
        // Free symbol names
        for (self.symbols.items) |sym| {
            self.allocator.free(sym.name);
        }
        self.symbols.deinit(self.allocator);
        self.relocations.deinit(self.allocator);
    }
    
    pub fn appendCode(self: *ELFObjectWriter, bytes: []const u8) !void {
        try self.code.appendSlice(self.allocator, bytes);
    }
    
    pub fn appendData(self: *ELFObjectWriter, bytes: []const u8) !u64 {
        const offset = self.data.items.len;
        try self.data.appendSlice(self.allocator, bytes);
        return @intCast(offset);
    }
    
    pub fn addSymbol(self: *ELFObjectWriter, name: []const u8, value: u64, size: u64, 
                     section: Symbol.Section, binding: Symbol.Binding, sym_type: Symbol.SymbolType) !u32 {
        const name_copy = try self.allocator.dupe(u8, name);
        const index = self.symbols.items.len;
        try self.symbols.append(self.allocator, .{
            .name = name_copy,
            .value = value,
            .size = size,
            .section = section,
            .binding = binding,
            .type = sym_type,
        });
        return @intCast(index);
    }
    
    pub fn addRelocation(self: *ELFObjectWriter, offset: u64, symbol_index: u32, 
                        rel_type: Relocation.RelocationType, addend: i64) !void {
        try self.relocations.append(self.allocator, .{
            .offset = offset,
            .symbol_index = symbol_index,
            .type = rel_type,
            .addend = addend,
        });
    }
    
    /// Write complete ELF object file to disk
    pub fn writeToFile(self: *ELFObjectWriter, io: std.Io, path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.createFile(io, path, .{});
        defer file.close(io);
        
        // Build string table for section names
        const empty_shstrtab = try self.allocator.alloc(u8, 0);
        var shstrtab = std.ArrayList(u8).fromOwnedSlice(empty_shstrtab);
        defer shstrtab.deinit(self.allocator);
        
        try shstrtab.append(self.allocator, 0); // Null string at index 0
        
        const shstrtab_idx = try addString(&shstrtab, self.allocator, ".shstrtab");
        const text_idx = try addString(&shstrtab, self.allocator, ".text");
        const data_idx = try addString(&shstrtab, self.allocator, ".data");
        const symtab_idx = try addString(&shstrtab, self.allocator, ".symtab");
        const strtab_idx = try addString(&shstrtab, self.allocator, ".strtab");
        const rela_text_idx = try addString(&shstrtab, self.allocator, ".rela.text");
        
        // Build string table for symbol names
        const empty_strtab = try self.allocator.alloc(u8, 0);
        var strtab = std.ArrayList(u8).fromOwnedSlice(empty_strtab);
        defer strtab.deinit(self.allocator);
        
        try strtab.append(self.allocator, 0); // Null string at index 0
        
        // Add symbol names to strtab and record their offsets
        var symbol_name_offsets = try self.allocator.alloc(u32, self.symbols.items.len);
        defer self.allocator.free(symbol_name_offsets);
        
        for (self.symbols.items, 0..) |sym, i| {
            symbol_name_offsets[i] = try addString(&strtab, self.allocator, sym.name);
        }
        
        // Calculate section offsets
        const ehdr_size: u64 = 64;
        const shdr_size: u64 = 64;
        
        // Section layout:
        // 0: NULL
        // 1: .text
        // 2: .data  
        // 3: .shstrtab
        // 4: .symtab
        // 5: .strtab
        // 6: .rela.text
        const num_sections: u16 = if (self.relocations.items.len > 0) 7 else 6;
        
        const shdr_offset = ehdr_size;
        const text_offset = shdr_offset + (num_sections * shdr_size);
        const data_offset = text_offset + self.code.items.len;
        const shstrtab_offset = data_offset + self.data.items.len;
        const strtab_offset = shstrtab_offset + shstrtab.items.len;
        
        // Symbol table: each entry is 24 bytes
        const symtab_entry_size: u64 = 24;
        const symtab_size = (self.symbols.items.len + 1) * symtab_entry_size; // +1 for null symbol
        const symtab_offset = strtab_offset + strtab.items.len;
        
        // Relocation table: each entry is 24 bytes
        const rela_entry_size: u64 = 24;
        const rela_size = self.relocations.items.len * rela_entry_size;
        const rela_offset = symtab_offset + symtab_size;
        
        const empty_buffer = try self.allocator.alloc(u8, 0);
        var buffer = std.ArrayList(u8).fromOwnedSlice(empty_buffer);
        defer buffer.deinit(self.allocator);
        
        // ELF Header (64 bytes)
        try buffer.appendSlice(self.allocator, &[_]u8{
            0x7F, 'E', 'L', 'F',    // Magic
            2,                       // 64-bit
            1,                       // Little endian
            1,                       // ELF version
            0,                       // System V ABI
            0, 0, 0, 0, 0, 0, 0, 0, // Padding
        });
        
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 1)));  // e_type: ET_REL (relocatable)
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0x3E))); // e_machine: x86-64
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // e_version
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));  // e_entry: no entry point
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));  // e_phoff: no program headers
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(shdr_offset));   // e_shoff: section header offset
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 0)));  // e_flags
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 64))); // e_ehsize
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0)));  // e_phentsize: no program headers
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0)));  // e_phnum
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 64))); // e_shentsize
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(num_sections)); // e_shnum
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 3)));  // e_shstrndx: .shstrtab section index
        
        // Section Headers
        // Section 0: NULL
        try writeSectionHeader(&buffer, self.allocator, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        
        // Section 1: .text
        try writeSectionHeader(&buffer, self.allocator, 
            text_idx,           // sh_name
            1,                  // sh_type: SHT_PROGBITS
            6,                  // sh_flags: SHF_ALLOC | SHF_EXECINSTR
            0,                  // sh_addr
            text_offset,        // sh_offset
            self.code.items.len, // sh_size
            0,                  // sh_link
            0,                  // sh_info
            16,                 // sh_addralign
            0                   // sh_entsize
        );
        
        // Section 2: .data
        try writeSectionHeader(&buffer, self.allocator,
            data_idx,           // sh_name
            1,                  // sh_type: SHT_PROGBITS
            3,                  // sh_flags: SHF_ALLOC | SHF_WRITE
            0,                  // sh_addr
            data_offset,        // sh_offset
            self.data.items.len, // sh_size
            0,                  // sh_link
            0,                  // sh_info
            8,                  // sh_addralign
            0                   // sh_entsize
        );
        
        // Section 3: .shstrtab
        try writeSectionHeader(&buffer, self.allocator,
            shstrtab_idx,       // sh_name
            3,                  // sh_type: SHT_STRTAB
            0,                  // sh_flags
            0,                  // sh_addr
            shstrtab_offset,    // sh_offset
            shstrtab.items.len, // sh_size
            0,                  // sh_link
            0,                  // sh_info
            1,                  // sh_addralign
            0                   // sh_entsize
        );
        
        // Section 4: .symtab
        try writeSectionHeader(&buffer, self.allocator,
            symtab_idx,         // sh_name
            2,                  // sh_type: SHT_SYMTAB
            0,                  // sh_flags
            0,                  // sh_addr
            symtab_offset,      // sh_offset
            symtab_size,        // sh_size
            5,                  // sh_link: .strtab section index
            1,                  // sh_info: first non-local symbol
            8,                  // sh_addralign
            24                  // sh_entsize: sizeof(Elf64_Sym)
        );
        
        // Section 5: .strtab
        try writeSectionHeader(&buffer, self.allocator,
            strtab_idx,         // sh_name
            3,                  // sh_type: SHT_STRTAB
            0,                  // sh_flags
            0,                  // sh_addr
            strtab_offset,      // sh_offset
            strtab.items.len,   // sh_size
            0,                  // sh_link
            0,                  // sh_info
            1,                  // sh_addralign
            0                   // sh_entsize
        );
        
        // Section 6: .rela.text (if we have relocations)
        if (self.relocations.items.len > 0) {
            try writeSectionHeader(&buffer, self.allocator,
                rela_text_idx,      // sh_name
                4,                  // sh_type: SHT_RELA
                0,                  // sh_flags
                0,                  // sh_addr
                rela_offset,        // sh_offset
                rela_size,          // sh_size
                4,                  // sh_link: .symtab section index
                1,                  // sh_info: .text section index
                8,                  // sh_addralign
                24                  // sh_entsize: sizeof(Elf64_Rela)
            );
        }
        
        // .text section data
        try buffer.appendSlice(self.allocator, self.code.items);
        
        // .data section data
        try buffer.appendSlice(self.allocator, self.data.items);
        
        // .shstrtab section data
        try buffer.appendSlice(self.allocator, shstrtab.items);
        
        // .strtab section data
        try buffer.appendSlice(self.allocator, strtab.items);
        
        // .symtab section data
        // Null symbol
        try writeSymbol(&buffer, self.allocator, 0, 0, 0, 0, 0, 0);
        
        // User symbols
        for (self.symbols.items, 0..) |sym, i| {
            const info = (@as(u8, @intFromEnum(sym.binding)) << 4) | @intFromEnum(sym.type);
            try writeSymbol(&buffer, self.allocator,
                symbol_name_offsets[i],
                info,
                0, // st_other
                @intFromEnum(sym.section),
                sym.value,
                sym.size
            );
        }
        
        // .rela.text section data
        if (self.relocations.items.len > 0) {
            for (self.relocations.items) |reloc| {
                const r_info = (@as(u64, reloc.symbol_index + 1) << 32) | @intFromEnum(reloc.type);
                try buffer.appendSlice(self.allocator, &std.mem.toBytes(reloc.offset));
                try buffer.appendSlice(self.allocator, &std.mem.toBytes(r_info));
                try buffer.appendSlice(self.allocator, &std.mem.toBytes(reloc.addend));
            }
        }
        
        // Write to file
        try file.writeStreamingAll(io, buffer.items);
    }
};

fn addString(list: *std.ArrayList(u8), allocator: Allocator, s: []const u8) !u32 {
    const offset: u32 = @intCast(list.items.len);
    try list.appendSlice(allocator, s);
    try list.append(allocator, 0); // Null terminator
    return offset;
}

fn writeSectionHeader(buffer: *std.ArrayList(u8), allocator: Allocator, name: u32, sh_type: u32, flags: u64,
                      addr: u64, offset: u64, size: u64, link: u32, info: u32,
                      addralign: u64, entsize: u64) !void {
    try buffer.appendSlice(allocator, &std.mem.toBytes(name));
    try buffer.appendSlice(allocator, &std.mem.toBytes(sh_type));
    try buffer.appendSlice(allocator, &std.mem.toBytes(flags));
    try buffer.appendSlice(allocator, &std.mem.toBytes(addr));
    try buffer.appendSlice(allocator, &std.mem.toBytes(offset));
    try buffer.appendSlice(allocator, &std.mem.toBytes(size));
    try buffer.appendSlice(allocator, &std.mem.toBytes(link));
    try buffer.appendSlice(allocator, &std.mem.toBytes(info));
    try buffer.appendSlice(allocator, &std.mem.toBytes(addralign));
    try buffer.appendSlice(allocator, &std.mem.toBytes(entsize));
}

fn writeSymbol(buffer: *std.ArrayList(u8), allocator: Allocator, name: u32, info: u8, other: u8,
               shndx: u16, value: u64, size: u64) !void {
    try buffer.appendSlice(allocator, &std.mem.toBytes(name));
    try buffer.append(allocator, info);
    try buffer.append(allocator, other);
    try buffer.appendSlice(allocator, &std.mem.toBytes(shndx));
    try buffer.appendSlice(allocator, &std.mem.toBytes(value));
    try buffer.appendSlice(allocator, &std.mem.toBytes(size));
}
