const std = @import("std");
const Allocator = std.mem.Allocator;
const ELFObjectReader = @import("elf_reader.zig").ELFObjectReader;
const ELFWriter = @import("../codegen/elf_writer.zig").ELFWriter;

/// HolyC Linker - Links object files into executables
pub const Linker = struct {
    allocator: Allocator,
    objects: std.ArrayList(*ELFObjectReader),
    symbols: std.StringHashMap(ResolvedSymbol),
    external_symbols: std.ArrayList(ExternalSymbol),
    entry_point: ?[]const u8,
    base_address: u64,
    
    pub const ExternalSymbol = struct {
        name: []const u8,
        plt_offset: u64,
        got_offset: u64,
    };
    
    pub const ResolvedSymbol = struct {
        name: []const u8,
        value: u64, // Final address after linking
        size: u64,
        object_index: usize,
        section_index: u16,
    };
    
    pub const LinkerError = error{
        UndefinedSymbol,
        MultipleDefinition,
        NoEntryPoint,
        InvalidRelocation,
    } || Allocator.Error;
    
    pub fn init(allocator: Allocator) !Linker {
        const empty_objects = try allocator.alloc(*ELFObjectReader, 0);
        const empty_externals = try allocator.alloc(ExternalSymbol, 0);
        return .{
            .allocator = allocator,
            .objects = std.ArrayList(*ELFObjectReader).fromOwnedSlice(empty_objects),
            .symbols = std.StringHashMap(ResolvedSymbol).init(allocator),
            .external_symbols = std.ArrayList(ExternalSymbol).fromOwnedSlice(empty_externals),
            .entry_point = null,
            .base_address = 0x400000, // Standard Linux load address
        };
    }
    
    pub fn deinit(self: *Linker) void {
        // Free all object readers
        for (self.objects.items) |obj| {
            obj.deinit();
            self.allocator.destroy(obj);
        }
        self.objects.deinit(self.allocator);
        
        // Free symbol table
        var it = self.symbols.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.symbols.deinit();
        
        // Free external symbols
        for (self.external_symbols.items) |ext| {
            self.allocator.free(ext.name);
        }
        self.external_symbols.deinit(self.allocator);
    }
    
    pub fn addObject(self: *Linker, data: []const u8) !void {
        const obj = try self.allocator.create(ELFObjectReader);
        obj.* = try ELFObjectReader.init(self.allocator, data);
        try obj.parse();
        try self.objects.append(self.allocator, obj);
    }
    
    pub fn setEntryPoint(self: *Linker, name: []const u8) void {
        self.entry_point = name;
    }
    
    pub fn link(self: *Linker, output_path: []const u8, io: std.Io) !void {
        std.debug.print("HolyC Linker - Linking {} object(s)\n\n", .{self.objects.items.len});
        
        // Phase 1: Collect external symbols
        std.debug.print("[1/5] Collecting external symbols...\n", .{});
        try self.collectExternalSymbols();
        if (self.external_symbols.items.len > 0) {
            std.debug.print("      Found {} external symbol(s)\n", .{self.external_symbols.items.len});
            for (self.external_symbols.items) |ext| {
                std.debug.print("        - {s}\n", .{ext.name});
            }
        }
        
        // Phase 2: Collect all sections and calculate addresses
        std.debug.print("[2/5] Collecting sections...\n", .{});
        const layout = try self.computeLayout();
        defer self.freeLayout(layout);
        
        // Phase 3: Resolve symbols
        std.debug.print("[3/5] Resolving symbols...\n", .{});
        try self.resolveSymbols(layout);
        
        // Phase 4: Apply relocations
        std.debug.print("[4/5] Applying relocations...\n", .{});
        const relocated_sections = try self.applyRelocations(layout);
        defer self.freeRelocatedSections(relocated_sections);
        
        // Phase 5: Generate executable
        std.debug.print("[5/5] Writing executable...\n", .{});
        try self.writeExecutable(layout, relocated_sections, output_path, io);
        
        std.debug.print("\n✓ Link successful!\n", .{});
        std.debug.print("Output: {s}\n", .{output_path});
    }
    
    fn collectExternalSymbols(self: *Linker) !void {
        // Scan all objects for undefined symbols (shndx == 0)
        for (self.objects.items) |obj| {
            for (obj.symbols) |symbol| {
                if (symbol.shndx != 0) continue; // Skip defined symbols
                if (symbol.name.len == 0) continue; // Skip NULL symbol
                
                // Check if we already have this external symbol
                var found = false;
                for (self.external_symbols.items) |ext| {
                    if (std.mem.eql(u8, ext.name, symbol.name)) {
                        found = true;
                        break;
                    }
                }
                
                if (!found) {
                    const name_copy = try self.allocator.dupe(u8, symbol.name);
                    try self.external_symbols.append(self.allocator, .{
                        .name = name_copy,
                        .plt_offset = 0,
                        .got_offset = 0,
                    });
                }
            }
        }
    }
    
    const SectionLayout = struct {
        object_index: usize,
        section_index: usize,
        section_name: []const u8,
        vaddr: u64,
        size: u64,
        data: []const u8,
        is_code: bool,
    };
    
    const Layout = struct {
        text_sections: []SectionLayout,
        data_sections: []SectionLayout,
        code_size: u64,
        data_size: u64,
        plt_addr: u64,
        plt_size: u64,
        got_addr: u64,
        got_size: u64,
        code_offset: u64, // File offset where code starts (after RO dynamic sections)
    };
    
    fn computeLayout(self: *Linker) !*Layout {
        const empty_text = try self.allocator.alloc(SectionLayout, 0);
        var text_list = std.ArrayList(SectionLayout).fromOwnedSlice(empty_text);
        defer text_list.deinit(self.allocator);

        const empty_data = try self.allocator.alloc(SectionLayout, 0);
        var data_list = std.ArrayList(SectionLayout).fromOwnedSlice(empty_data);
        defer data_list.deinit(self.allocator);
        
        // Calculate initial code offset
        // For dynamic executables, RO dynamic sections (interp, hash, dynsym, dynstr, rela.plt)
        // are placed before code in the second PT_LOAD segment
        var code_offset: u64 = 0x1000; // Default: right after headers
        if (self.external_symbols.items.len > 0) {
            const num_ext_syms = self.external_symbols.items.len;
            // PT_INTERP: "/lib64/ld-linux-x86-64.so.2\0" (28 bytes) + alignment
            const interp_size: u64 = 28;
            const interp_aligned = (code_offset + interp_size + 7) & ~@as(u64, 7);
            
            // Hash table: (2 + nbucket + nchain) * 4 bytes
            const hash_size: u64 = (2 + 1 + 1 + num_ext_syms) * 4;
            const hash_aligned = (interp_aligned + hash_size + 7) & ~@as(u64, 7);
            
            // .dynsym: (1 NULL + N symbols) * 24 bytes
            const dynsym_size: u64 = (1 + num_ext_syms) * 24;
            const dynsym_aligned = (hash_aligned + dynsym_size + 7) & ~@as(u64, 7);
            
            // .dynstr: "\0libc.so.6\0" + symbol names (rough estimate)
            // For puts: "\0libc.so.6\0puts\0" = 1 + 9 + 1 + 4 + 1 = 16 bytes
            const dynstr_size: u64 = 1 + 10 + num_ext_syms * 5; // Better estimate
            const dynstr_aligned = (dynsym_aligned + dynstr_size + 7) & ~@as(u64, 7);
            
            // .rela.plt: N relocations * 24 bytes
            const rela_plt_size: u64 = num_ext_syms * 24;
            code_offset = (dynstr_aligned + rela_plt_size + 7) & ~@as(u64, 7);
            
            std.debug.print("DEBUG: RO dynamic overhead: 0x{x}, code starts at offset 0x{x}\n", .{code_offset - 0x1000, code_offset});
        }
        
        const code_start = self.base_address + code_offset;
        var current_code_addr = code_start;
        var current_data_addr: u64 = 0;
        
        // Collect .text sections
        for (self.objects.items, 0..) |obj, obj_idx| {
            for (obj.sections, 0..) |section, sec_idx| {
                if (std.mem.eql(u8, section.name, ".text")) {
                    try text_list.append(self.allocator, .{
                        .object_index = obj_idx,
                        .section_index = sec_idx,
                        .section_name = section.name,
                        .vaddr = current_code_addr,
                        .size = section.size,
                        .data = section.data,
                        .is_code = true,
                    });
                    current_code_addr += section.size;
                }
            }
        }
        
        // Account for PLT size when calculating data section start
        // PLT: 16 byte header + 16 bytes per symbol
        const plt_size = if (self.external_symbols.items.len > 0)
            16 + (self.external_symbols.items.len * 16)
        else
            0;
        
        // Align code size (including PLT), then add to code_offset to get data_offset
        // This matches ELFWriter.writeToFile calculation
        const actual_code_size = current_code_addr - code_start;
        const code_size_aligned = (actual_code_size + plt_size + 0xFFF) & ~@as(u64, 0xFFF);
        const data_start = code_offset + code_size_aligned;
        std.debug.print("DEBUG: code_offset=0x{x}, actual_code_size=0x{x}, plt_size=0x{x}, aligned=0x{x}, data_start=0x{x}\n", .{code_offset, actual_code_size, plt_size, code_size_aligned, data_start});
        
        // For dynamic executables, account for space needed by .dynamic and GOT
        // These will be written before user .data sections in the RW segment
        // Note: hash, dynsym, dynstr, rela.plt are in the RO segment, not counted here
        var data_overhead: u64 = 0;
        if (self.external_symbols.items.len > 0) {
            const num_ext_syms = self.external_symbols.items.len;
            const got_size = (3 + num_ext_syms) * 8;
            const dyn_section_size: u64 = 240; // ~15 entries * 16 bytes
            
            data_overhead = dyn_section_size + got_size;
            data_overhead = (data_overhead + 7) & ~@as(u64, 7); // Align to 8 bytes
        }
        
        current_data_addr = data_start + self.base_address + data_overhead;
        
        // Collect .data sections
        for (self.objects.items, 0..) |obj, obj_idx| {
            for (obj.sections, 0..) |section, sec_idx| {
                if (std.mem.eql(u8, section.name, ".data")) {
                    std.debug.print("DEBUG: .data section from obj {}: size={}, vaddr=0x{x}, overhead=0x{x}\n", .{obj_idx, section.size, current_data_addr, data_overhead});
                    try data_list.append(self.allocator, .{
                        .object_index = obj_idx,
                        .section_index = sec_idx,
                        .section_name = section.name,
                        .vaddr = current_data_addr,
                        .size = section.size,
                        .data = section.data,
                        .is_code = false,
                    });
                    current_data_addr += section.size;
                }
            }
        }
        
        // Reserve space for PLT and GOT if we have external symbols
        // PLT entry size: 16 bytes per entry + 16 byte header (already calculated above)
        // GOT entry size: 8 bytes per entry + 24 bytes for GOT[0..2]
        const num_external = self.external_symbols.items.len;
        
        const plt_addr = current_code_addr;
        const got_addr = current_data_addr;
        
        const total_code_size = current_code_addr - code_start + plt_size;
        const total_data_size = current_data_addr - (data_start + self.base_address) + data_overhead;
        
        // Assign PLT and GOT offsets to each external symbol
        for (self.external_symbols.items, 0..) |*ext, i| {
            ext.plt_offset = plt_addr + 16 + (i * 16); // After PLT header
            ext.got_offset = got_addr + 24 + (i * 8);  // After GOT[0..2]
        }
        
        const layout = try self.allocator.create(Layout);
        layout.* = .{
            .text_sections = try text_list.toOwnedSlice(self.allocator),
            .data_sections = try data_list.toOwnedSlice(self.allocator),
            .code_size = total_code_size,
            .data_size = total_data_size,
            .plt_addr = plt_addr,
            .plt_size = plt_size,
            .got_addr = got_addr,
            .got_size = if (num_external > 0) 24 + (num_external * 8) else 0,
            .code_offset = code_offset,
        };
        
        return layout;
    }
    
    fn resolveSymbols(self: *Linker, layout: *const Layout) !void {
        // First pass: collect all global symbols
        for (self.objects.items, 0..) |obj, obj_idx| {
            for (obj.symbols) |symbol| {
                if (symbol.shndx == 0) continue; // Undefined symbol
                if (!symbol.isGlobal()) continue; // Only resolve globals
                
                // Find the section this symbol is in
                const section_vaddr = self.findSectionVAddr(layout, obj_idx, symbol.shndx) orelse continue;
                
                const final_addr = section_vaddr + symbol.value;
                
                // Check for multiple definitions
                if (self.symbols.contains(symbol.name)) {
                    std.debug.print("Error: Multiple definition of symbol '{s}'\n", .{symbol.name});
                    return LinkerError.MultipleDefinition;
                }
                
                const name_copy = try self.allocator.dupe(u8, symbol.name);
                try self.symbols.put(name_copy, .{
                    .name = name_copy,
                    .value = final_addr,
                    .size = symbol.size,
                    .object_index = obj_idx,
                    .section_index = symbol.shndx,
                });
            }
        }
        
        std.debug.print("      Resolved {} global symbol(s)\n", .{self.symbols.count()});
    }
    
    fn findSectionVAddr(_: *Linker, layout: *const Layout, obj_idx: usize, section_idx: u16) ?u64 {
        // Check .text sections
        // Note: section_idx is ELF section index (includes NULL section at 0)
        // Our stored section_index is also the ELF section index
        for (layout.text_sections) |sec| {
            if (sec.object_index == obj_idx and sec.section_index == section_idx) {
                return sec.vaddr;
            }
        }
        
        // Check .data sections
        for (layout.data_sections) |sec| {
            if (sec.object_index == obj_idx and sec.section_index == section_idx) {
                return sec.vaddr;
            }
        }
        
        return null;
    }
    
    const RelocatedSection = struct {
        data: []u8,
        vaddr: u64,
    };
    
    fn applyRelocations(self: *Linker, layout: *const Layout) ![]RelocatedSection {
        var relocated = try self.allocator.alloc(RelocatedSection, layout.text_sections.len);
        
        // Copy and relocate .text sections
        for (layout.text_sections, 0..) |section_layout, idx| {
            // Make a mutable copy of the section data
            const data_copy = try self.allocator.dupe(u8, section_layout.data);
            relocated[idx] = .{
                .data = data_copy,
                .vaddr = section_layout.vaddr,
            };
            
            // Apply relocations for this section
            const obj = self.objects.items[section_layout.object_index];
            for (obj.relocations) |reloc| {
                // Check if this relocation applies to this section
                // The relocation section_index should match the section we're processing
                if (reloc.section_index != section_layout.section_index) continue;
                
                // Get the symbol being referenced
                const sym_idx = reloc.symIndex();
                if (sym_idx >= obj.symbols.len) return LinkerError.InvalidRelocation;
                
                const symbol = obj.symbols[sym_idx];
                
                // Get the symbol's final address
                const symbol_addr = if (symbol.shndx == 0) blk: {
                    // Undefined symbol - look it up in global symbols first
                    const resolved = self.symbols.get(symbol.name) orelse {
                        // Not in our objects - look for external symbol
                        var ext_addr: ?u64 = null;
                        for (self.external_symbols.items) |ext| {
                            if (std.mem.eql(u8, ext.name, symbol.name)) {
                                ext_addr = ext.plt_offset;
                                std.debug.print("DEBUG: External symbol '{s}' -> PLT at 0x{x}\n", .{ext.name, ext.plt_offset});
                                break;
                            }
                        }
                        
                        if (ext_addr) |addr| {
                            break :blk addr;
                        } else {
                            // This shouldn't happen if collectExternalSymbols worked correctly
                            std.debug.print("Error: Undefined symbol '{s}'\n", .{symbol.name});
                            return LinkerError.UndefinedSymbol;
                        }
                    };
                    break :blk resolved.value;
                } else blk: {
                    // Defined in this object - calculate address
                    const sec_vaddr = self.findSectionVAddr(layout, section_layout.object_index, symbol.shndx) orelse return LinkerError.InvalidRelocation;
                    std.debug.print("DEBUG: Relocating defined symbol, section shndx={}, sec_vaddr=0x{x}, symbol.value={}, final=0x{x}\n", .{symbol.shndx, sec_vaddr, symbol.value, sec_vaddr + symbol.value});
                    break :blk sec_vaddr + symbol.value;
                };
                
                // Apply the relocation based on type
                const reloc_type = reloc.relType();
                const offset_in_section = reloc.offset;
                
                if (offset_in_section + 8 > data_copy.len) return LinkerError.InvalidRelocation;
                
                switch (reloc_type) {
                    2, 4 => { // R_X86_64_PC32 or R_X86_64_PLT32 - PC-relative 32-bit
                        const patch_addr = section_layout.vaddr + offset_in_section;
                        const value: i64 = @as(i64, @intCast(symbol_addr)) + reloc.addend - @as(i64, @intCast(patch_addr));
                        std.debug.print("DEBUG: PLT32 reloc: symbol_addr=0x{x}, patch_addr=0x{x}, addend={}, value=0x{x}\n", .{symbol_addr, patch_addr, reloc.addend, value});
                        std.mem.writeInt(i32, data_copy[offset_in_section..][0..4], @intCast(value), .little);
                    },
                    1 => { // R_X86_64_64 - Direct 64-bit
                        const value: u64 = symbol_addr + @as(u64, @intCast(reloc.addend));
                        std.mem.writeInt(u64, data_copy[offset_in_section..][0..8], value, .little);
                    },
                    10 => { // R_X86_64_32 - Direct 32-bit zero-extend
                        const value: u32 = @intCast(symbol_addr + @as(u64, @intCast(reloc.addend)));
                        std.mem.writeInt(u32, data_copy[offset_in_section..][0..4], value, .little);
                    },
                    11 => { // R_X86_64_32S - Direct 32-bit sign-extend
                        const value: i32 = @intCast(@as(i64, @intCast(symbol_addr)) + reloc.addend);
                        std.mem.writeInt(i32, data_copy[offset_in_section..][0..4], value, .little);
                    },
                    else => {
                        std.debug.print("Warning: Unsupported relocation type {}\n", .{reloc_type});
                    },
                }
            }
        }
        
        return relocated;
    }
    
    fn writeExecutable(self: *Linker, layout: *const Layout, relocated: []RelocatedSection, output_path: []const u8, io: std.Io) !void {
        var elf = try ELFWriter.init(self.allocator);
        defer elf.deinit();
        
        // Append all relocated code sections
        for (relocated) |section| {
            try elf.appendCode(section.data);
        }
        
        // Generate PLT/GOT and dynamic sections if we have external symbols
        if (self.external_symbols.items.len > 0) {
            // Add dynamic symbols to ELF writer
            for (self.external_symbols.items) |ext| {
                try elf.addDynamicSymbol(ext.name, ext.plt_offset, ext.got_offset);
            }
            
            // Generate dynamic string/symbol sections early (don't depend on addresses)
            var string_offsets = try elf.generateDynStr();
            defer string_offsets.deinit();
            
            try elf.generateDynSym(string_offsets);
            
            // PLT, GOT, hash, rela.plt, and dynamic sections will be generated
            // in writeToFile after final addresses are calculated
        }
        
        // Append all data sections
        // The ELF writer will place these after .dynamic and GOT in the final binary
        for (layout.data_sections) |section| {
            _ = try elf.appendData(section.data);
        }
        
        // Now that we have final addresses, apply relocations again with correct data vaddrs
        // We need to re-apply relocations for data sections only
        // (Placeholder for future two-pass relocation implementation)
        
        // Set entry point
        const entry_name = self.entry_point orelse "_start";
        const entry_symbol = self.symbols.get(entry_name) orelse {
            std.debug.print("Error: Entry point '{s}' not found\n", .{entry_name});
            return LinkerError.NoEntryPoint;
        };
        
        const entry_offset: u32 = @intCast(entry_symbol.value - (self.base_address + layout.code_offset));
        std.debug.print("DEBUG: Entry point '{s}' at vaddr 0x{x}, offset 0x{x}\n", .{entry_name, entry_symbol.value, entry_offset});
        try elf.setEntryPoint(entry_offset);
        
        // Write the executable
        try elf.writeToFile(io, output_path);
    }
    
    fn freeLayout(self: *Linker, layout: *Layout) void {
        self.allocator.free(layout.text_sections);
        self.allocator.free(layout.data_sections);
        self.allocator.destroy(layout);
    }
    
    fn freeRelocatedSections(self: *Linker, sections: []RelocatedSection) void {
        for (sections) |section| {
            self.allocator.free(section.data);
        }
        self.allocator.free(sections);
    }
};
