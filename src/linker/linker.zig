const std = @import("std");
const Allocator = std.mem.Allocator;
const ELFObjectReader = @import("elf_reader.zig").ELFObjectReader;
const ELFWriter = @import("../codegen/elf_writer.zig").ELFWriter;

/// HolyC Linker - Links object files into executables
pub const Linker = struct {
    allocator: Allocator,
    objects: std.ArrayList(*ELFObjectReader),
    symbols: std.StringHashMap(ResolvedSymbol),
    external_libs: std.ArrayList([]const u8), // Paths to shared libraries
    external_symbols: std.StringHashMap(void), // Symbols to import from shared libs
    entry_point: ?[]const u8,
    base_address: u64,
    
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
        const empty_libs = try allocator.alloc([]const u8, 0);
        return .{
            .allocator = allocator,
            .objects = std.ArrayList(*ELFObjectReader).fromOwnedSlice(empty_objects),
            .symbols = std.StringHashMap(ResolvedSymbol).init(allocator),
            .external_libs = std.ArrayList([]const u8).fromOwnedSlice(empty_libs),
            .external_symbols = std.StringHashMap(void).init(allocator),
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
        
        // Free external libs
        for (self.external_libs.items) |lib_path| {
            self.allocator.free(lib_path);
        }
        self.external_libs.deinit(self.allocator);
        
        // Free external symbols
        var ext_it = self.external_symbols.keyIterator();
        while (ext_it.next()) |key| {
            self.allocator.free(key.*);
        }
        self.external_symbols.deinit();
    }
    
    pub fn addLibrary(self: *Linker, lib_path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, lib_path);
        try self.external_libs.append(self.allocator, path_copy);
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
        
        // Phase 1: Collect all sections and calculate addresses
        std.debug.print("[1/4] Collecting sections...\n", .{});
        const layout = try self.computeLayout();
        defer self.freeLayout(layout);
        
        // Phase 2: Resolve symbols
        std.debug.print("[2/4] Resolving symbols...\n", .{});
        try self.resolveSymbols(layout);
        
        // Phase 3: Apply relocations
        std.debug.print("[3/4] Applying relocations...\n", .{});
        const relocated_sections = try self.applyRelocations(layout);
        defer self.freeRelocatedSections(relocated_sections);
        
        // Phase 4: Generate executable
        std.debug.print("[4/4] Writing executable...\n", .{});
        try self.writeExecutable(layout, relocated_sections, output_path, io);
        
        std.debug.print("\n✓ Link successful!\n", .{});
        std.debug.print("Output: {s}\n", .{output_path});
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
    };
    
    fn computeLayout(self: *Linker) !*Layout {
        const empty_text = try self.allocator.alloc(SectionLayout, 0);
        var text_list = std.ArrayList(SectionLayout).fromOwnedSlice(empty_text);
        defer text_list.deinit(self.allocator);

        const empty_data = try self.allocator.alloc(SectionLayout, 0);
        var data_list = std.ArrayList(SectionLayout).fromOwnedSlice(empty_data);
        defer data_list.deinit(self.allocator);
        
        const code_start = self.base_address + 0x1000; // After ELF header
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
        
        // Align data section
        const data_start = ((current_code_addr - self.base_address) + 0xFFF) & ~@as(u64, 0xFFF);
        current_data_addr = data_start + self.base_address;
        
        // Collect .data sections
        for (self.objects.items, 0..) |obj, obj_idx| {
            for (obj.sections, 0..) |section, sec_idx| {
                if (std.mem.eql(u8, section.name, ".data")) {
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
        
        const layout = try self.allocator.create(Layout);
        layout.* = .{
            .text_sections = try text_list.toOwnedSlice(self.allocator),
            .data_sections = try data_list.toOwnedSlice(self.allocator),
            .code_size = current_code_addr - code_start,
            .data_size = current_data_addr - (data_start + self.base_address),
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
                if (reloc.section_index != section_layout.section_index + 1) continue;
                
                // Get the symbol being referenced
                const sym_idx = reloc.symIndex();
                if (sym_idx >= obj.symbols.len) return LinkerError.InvalidRelocation;
                
                const symbol = obj.symbols[sym_idx];
                
                // Get the symbol's final address
                const symbol_addr = if (symbol.shndx == 0) blk: {
                    // Undefined symbol - look it up in global symbols
                    const resolved = self.symbols.get(symbol.name) orelse {
                        // Not in our objects - mark as external symbol
                        const sym_name_copy = try self.allocator.dupe(u8, symbol.name);
                        try self.external_symbols.put(sym_name_copy, {});
                        std.debug.print("      Marking '{s}' as external symbol\n", .{symbol.name});
                        // For now, use placeholder address 0 - will be resolved at runtime
                        break :blk 0;
                    };
                    break :blk resolved.value;
                } else blk: {
                    // Defined in this object - calculate address
                    const sec_vaddr = self.findSectionVAddr(layout, section_layout.object_index, symbol.shndx) orelse return LinkerError.InvalidRelocation;
                    break :blk sec_vaddr + symbol.value;
                };
                
                // Apply the relocation based on type
                const reloc_type = reloc.relType();
                const offset_in_section = reloc.offset;
                
                if (offset_in_section + 8 > data_copy.len) return LinkerError.InvalidRelocation;
                
                switch (reloc_type) {
                    2 => { // R_X86_64_PC32 - PC-relative 32-bit
                        const patch_addr = section_layout.vaddr + offset_in_section;
                        const value: i64 = @as(i64, @intCast(symbol_addr)) + reloc.addend - @as(i64, @intCast(patch_addr));
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
        
        // Append all data sections
        for (layout.data_sections) |section| {
            _ = try elf.appendData(section.data);
        }
        
        // Set entry point
        const entry_name = self.entry_point orelse "_start";
        const entry_symbol = self.symbols.get(entry_name) orelse {
            std.debug.print("Error: Entry point '{s}' not found\n", .{entry_name});
            return LinkerError.NoEntryPoint;
        };
        
        const entry_offset: u32 = @intCast(entry_symbol.value - (self.base_address + 0x1000));
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
