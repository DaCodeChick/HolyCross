const std = @import("std");
const Allocator = std.mem.Allocator;

/// ELF64 object file reader
/// Parses relocatable object files for linking
pub const ELFObjectReader = struct {
    allocator: Allocator,
    data: []const u8,
    
    // Parsed sections
    sections: []Section,
    symbols: []Symbol,
    relocations: []Relocation,
    string_table: []const u8,
    
    pub const Section = struct {
        name: []const u8,
        type: u32,
        flags: u64,
        addr: u64,
        offset: u64,
        size: u64,
        link: u32,
        info: u32,
        addralign: u64,
        entsize: u64,
        data: []const u8,
    };
    
    pub const Symbol = struct {
        name: []const u8,
        value: u64,
        size: u64,
        info: u8,
        other: u8,
        shndx: u16,
        
        pub fn binding(self: Symbol) u8 {
            return self.info >> 4;
        }
        
        pub fn symType(self: Symbol) u8 {
            return self.info & 0xF;
        }
        
        pub fn isGlobal(self: Symbol) bool {
            return self.binding() == 1; // STB_GLOBAL
        }
        
        pub fn isLocal(self: Symbol) bool {
            return self.binding() == 0; // STB_LOCAL
        }
    };
    
    pub const Relocation = struct {
        offset: u64,
        info: u64,
        addend: i64,
        section_index: u32, // Which section this relocation applies to
        
        pub fn symIndex(self: Relocation) u32 {
            return @intCast(self.info >> 32);
        }
        
        pub fn relType(self: Relocation) u32 {
            return @intCast(self.info & 0xFFFFFFFF);
        }
    };
    
    pub fn init(allocator: Allocator, data: []const u8) !ELFObjectReader {
        return .{
            .allocator = allocator,
            .data = data,
            .sections = &.{},
            .symbols = &.{},
            .relocations = &.{},
            .string_table = &.{},
        };
    }
    
    pub fn deinit(self: *ELFObjectReader) void {
        // Free the data buffer (linker passes ownership)
        self.allocator.free(self.data);
        
        // Free allocated slices
        for (self.sections) |section| {
            self.allocator.free(section.name);
        }
        self.allocator.free(self.sections);
        
        for (self.symbols) |symbol| {
            self.allocator.free(symbol.name);
        }
        self.allocator.free(self.symbols);
        
        self.allocator.free(self.relocations);
    }
    
    pub fn parse(self: *ELFObjectReader) !void {
        // Verify ELF magic
        if (self.data.len < 64 or !std.mem.eql(u8, self.data[0..4], "\x7FELF")) {
            return error.InvalidELF;
        }
        
        // Read ELF header
        const e_shoff = std.mem.readInt(u64, self.data[40..48], .little);
        const e_shentsize = std.mem.readInt(u16, self.data[58..60], .little);
        const e_shnum = std.mem.readInt(u16, self.data[60..62], .little);
        const e_shstrndx = std.mem.readInt(u16, self.data[62..64], .little);
        
        // Read section headers
        const empty_sections = try self.allocator.alloc(Section, 0);
        var sections_list = std.ArrayList(Section).fromOwnedSlice(empty_sections);
        defer sections_list.deinit(self.allocator);
        
        var i: usize = 0;
        while (i < e_shnum) : (i += 1) {
            const shdr_offset = e_shoff + (i * e_shentsize);
            if (shdr_offset + 64 > self.data.len) return error.TruncatedFile;
            
            _ = std.mem.readInt(u32, self.data[shdr_offset..][0..4], .little); // sh_name (unused here)
            const sh_type = std.mem.readInt(u32, self.data[shdr_offset + 4..][0..4], .little);
            const sh_flags = std.mem.readInt(u64, self.data[shdr_offset + 8..][0..8], .little);
            const sh_addr = std.mem.readInt(u64, self.data[shdr_offset + 16..][0..8], .little);
            const sh_offset = std.mem.readInt(u64, self.data[shdr_offset + 24..][0..8], .little);
            const sh_size = std.mem.readInt(u64, self.data[shdr_offset + 32..][0..8], .little);
            const sh_link = std.mem.readInt(u32, self.data[shdr_offset + 40..][0..4], .little);
            const sh_info = std.mem.readInt(u32, self.data[shdr_offset + 44..][0..4], .little);
            const sh_addralign = std.mem.readInt(u64, self.data[shdr_offset + 48..][0..8], .little);
            const sh_entsize = std.mem.readInt(u64, self.data[shdr_offset + 56..][0..8], .little);
            
            // Get section data
            const section_data = if (sh_type != 8 and sh_offset + sh_size <= self.data.len) // SHT_NOBITS
                self.data[sh_offset..][0..@intCast(sh_size)]
            else
                &.{};
            
            try sections_list.append(self.allocator, .{
                .name = "", // Will be filled in later
                .type = sh_type,
                .flags = sh_flags,
                .addr = sh_addr,
                .offset = sh_offset,
                .size = sh_size,
                .link = sh_link,
                .info = sh_info,
                .addralign = sh_addralign,
                .entsize = sh_entsize,
                .data = section_data,
            });
            
            // Store string table section for later
            if (i == e_shstrndx) {
                self.string_table = section_data;
            }
        }
        
        // Fill in section names
        for (sections_list.items, 0..) |*section, idx| {
            const shdr_offset = e_shoff + (idx * e_shentsize);
            const name_offset = std.mem.readInt(u32, self.data[shdr_offset..][0..4], .little);
            const name = try self.readString(self.string_table, name_offset);
            section.name = try self.allocator.dupe(u8, name);
        }
        
        self.sections = try sections_list.toOwnedSlice(self.allocator);
        
        // Parse symbols
        try self.parseSymbols();
        
        // Parse relocations
        try self.parseRelocations();
    }
    
    fn parseSymbols(self: *ELFObjectReader) !void {
        // Find .symtab and .strtab
        const symtab_section = self.findSection(".symtab") orelse return;
        const strtab_section = self.findSection(".strtab") orelse return;
        
        const empty_symbols = try self.allocator.alloc(Symbol, 0);
        var symbols_list = std.ArrayList(Symbol).fromOwnedSlice(empty_symbols);
        defer symbols_list.deinit(self.allocator);
        
        const symtab_data = symtab_section.data;
        const strtab_data = strtab_section.data;
        const entry_size: usize = 24; // sizeof(Elf64_Sym)
        
        var offset: usize = 0;
        while (offset + entry_size <= symtab_data.len) : (offset += entry_size) {
            const st_name = std.mem.readInt(u32, symtab_data[offset..][0..4], .little);
            const st_info = symtab_data[offset + 4];
            const st_other = symtab_data[offset + 5];
            const st_shndx = std.mem.readInt(u16, symtab_data[offset + 6..][0..2], .little);
            const st_value = std.mem.readInt(u64, symtab_data[offset + 8..][0..8], .little);
            const st_size = std.mem.readInt(u64, symtab_data[offset + 16..][0..8], .little);
            
            const name = try self.readString(strtab_data, st_name);
            
            try symbols_list.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, name),
                .value = st_value,
                .size = st_size,
                .info = st_info,
                .other = st_other,
                .shndx = st_shndx,
            });
        }
        
        self.symbols = try symbols_list.toOwnedSlice(self.allocator);
    }
    
    fn parseRelocations(self: *ELFObjectReader) !void {
        const empty_relocs = try self.allocator.alloc(Relocation, 0);
        var relocs_list = std.ArrayList(Relocation).fromOwnedSlice(empty_relocs);
        defer relocs_list.deinit(self.allocator);
        
        for (self.sections) |section| {
            // Check if this is a relocation section (SHT_RELA = 4)
            if (section.type != 4) continue;
            
            const rela_data = section.data;
            const entry_size: usize = 24; // sizeof(Elf64_Rela)
            const target_section = section.info; // Which section these relocs apply to
            
            var offset: usize = 0;
            while (offset + entry_size <= rela_data.len) : (offset += entry_size) {
                const r_offset = std.mem.readInt(u64, rela_data[offset..][0..8], .little);
                const r_info = std.mem.readInt(u64, rela_data[offset + 8..][0..8], .little);
                const r_addend = std.mem.readInt(i64, rela_data[offset + 16..][0..8], .little);
                
                try relocs_list.append(self.allocator, .{
                    .offset = r_offset,
                    .info = r_info,
                    .addend = r_addend,
                    .section_index = target_section,
                });
            }
        }
        
        self.relocations = try relocs_list.toOwnedSlice(self.allocator);
    }
    
    fn findSection(self: *ELFObjectReader, name: []const u8) ?*const Section {
        for (self.sections) |*section| {
            if (std.mem.eql(u8, section.name, name)) {
                return section;
            }
        }
        return null;
    }
    
    fn readString(_: *ELFObjectReader, strtab: []const u8, offset: u32) ![]const u8 {
        if (offset >= strtab.len) return error.InvalidStringOffset;
        
        var end = offset;
        while (end < strtab.len and strtab[end] != 0) : (end += 1) {}
        
        return strtab[offset..end];
    }
};
