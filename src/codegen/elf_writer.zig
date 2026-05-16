const std = @import("std");
const Allocator = std.mem.Allocator;

/// ELF64 file writer for Linux x64 executables
/// Generates ELF files with optional dynamic linking support
pub const ELFWriter = struct {
    allocator: Allocator,
    code: std.ArrayList(u8),
    data: std.ArrayList(u8),
    plt: std.ArrayList(u8),
    got: std.ArrayList(u8),
    entry_point: u32,
    extern_symbols: std.ArrayList(ExternSymbol), // Track extern function calls
    dynamic_symbols: std.ArrayList(DynamicSymbol), // Symbols for .dynsym
    
    const ExternSymbol = struct {
        name: []const u8,
        call_site_offset: u32, // Offset in code where relocation is needed
    };
    
    const DynamicSymbol = struct {
        name: []const u8,
        plt_offset: u64,
        got_offset: u64,
    };
    
    pub fn init(allocator: Allocator) !ELFWriter {
        const empty_code = try allocator.alloc(u8, 0);
        const empty_data = try allocator.alloc(u8, 0);
        const empty_plt = try allocator.alloc(u8, 0);
        const empty_got = try allocator.alloc(u8, 0);
        const empty_externs = try allocator.alloc(ExternSymbol, 0);
        const empty_dynsyms = try allocator.alloc(DynamicSymbol, 0);
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).fromOwnedSlice(empty_code),
            .data = std.ArrayList(u8).fromOwnedSlice(empty_data),
            .plt = std.ArrayList(u8).fromOwnedSlice(empty_plt),
            .got = std.ArrayList(u8).fromOwnedSlice(empty_got),
            .entry_point = 0,
            .extern_symbols = std.ArrayList(ExternSymbol).fromOwnedSlice(empty_externs),
            .dynamic_symbols = std.ArrayList(DynamicSymbol).fromOwnedSlice(empty_dynsyms),
        };
    }
    
    pub fn deinit(self: *ELFWriter) void {
        self.code.deinit(self.allocator);
        self.data.deinit(self.allocator);
        self.plt.deinit(self.allocator);
        self.got.deinit(self.allocator);
        for (self.extern_symbols.items) |sym| {
            self.allocator.free(sym.name);
        }
        self.extern_symbols.deinit(self.allocator);
        for (self.dynamic_symbols.items) |sym| {
            self.allocator.free(sym.name);
        }
        self.dynamic_symbols.deinit(self.allocator);
    }
    
    pub fn addExternSymbol(self: *ELFWriter, name: []const u8, call_site_offset: u32) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.extern_symbols.append(self.allocator, .{
            .name = name_copy,
            .call_site_offset = call_site_offset,
        });
    }
    
    pub fn addDynamicSymbol(self: *ELFWriter, name: []const u8, plt_offset: u64, got_offset: u64) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        try self.dynamic_symbols.append(self.allocator, .{
            .name = name_copy,
            .plt_offset = plt_offset,
            .got_offset = got_offset,
        });
    }
    
    pub fn generatePLT(self: *ELFWriter, got_base_addr: u64) !void {
        // PLT[0] - PLT header (16 bytes)
        // pushq GOT[1]
        try self.plt.appendSlice(self.allocator, &[_]u8{ 0xFF, 0x35 });
        const got1_rel = @as(i32, @intCast(@as(i64, @intCast(got_base_addr + 8)) - @as(i64, @intCast(self.plt.items.len + 4))));
        try self.plt.appendSlice(self.allocator, &std.mem.toBytes(got1_rel));
        
        // jmpq *GOT[2]
        try self.plt.appendSlice(self.allocator, &[_]u8{ 0xFF, 0x25 });
        const got2_rel = @as(i32, @intCast(@as(i64, @intCast(got_base_addr + 16)) - @as(i64, @intCast(self.plt.items.len + 4))));
        try self.plt.appendSlice(self.allocator, &std.mem.toBytes(got2_rel));
        
        // nopl 0x0(%rax)
        try self.plt.appendSlice(self.allocator, &[_]u8{ 0x0F, 0x1F, 0x40, 0x00 });
        
        // Generate PLT entries for each dynamic symbol
        for (self.dynamic_symbols.items, 0..) |sym, i| {
            _ = sym;
            // PLT[i+1] - PLT entry (16 bytes each)
            // jmpq *GOT[i+3]
            try self.plt.appendSlice(self.allocator, &[_]u8{ 0xFF, 0x25 });
            const got_entry_addr = got_base_addr + 24 + (i * 8);
            const got_rel = @as(i32, @intCast(@as(i64, @intCast(got_entry_addr)) - @as(i64, @intCast(self.plt.items.len + 4))));
            try self.plt.appendSlice(self.allocator, &std.mem.toBytes(got_rel));
            
            // pushq $index
            try self.plt.appendSlice(self.allocator, &[_]u8{ 0x68 });
            try self.plt.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, @intCast(i))));
            
            // jmpq PLT[0]
            const plt0_offset = @as(i32, @intCast(-@as(i64, @intCast(self.plt.items.len + 5))));
            try self.plt.appendSlice(self.allocator, &[_]u8{ 0xE9 });
            try self.plt.appendSlice(self.allocator, &std.mem.toBytes(plt0_offset));
        }
    }
    
    pub fn generateGOT(self: *ELFWriter, dynamic_addr: u64, plt_base_addr: u64) !void {
        // GOT[0] = address of .dynamic section
        try self.got.appendSlice(self.allocator, &std.mem.toBytes(dynamic_addr));
        
        // GOT[1] = link_map (filled by dynamic linker)
        try self.got.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));
        
        // GOT[2] = dl_runtime_resolve (filled by dynamic linker)
        try self.got.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));
        
        // GOT entries for each PLT entry - point to PLT+6 initially
        for (self.dynamic_symbols.items, 0..) |_, i| {
            const plt_entry_addr = plt_base_addr + 16 + (i * 16) + 6; // PLT[i] + 6 bytes
            try self.got.appendSlice(self.allocator, &std.mem.toBytes(plt_entry_addr));
        }
    }
    
    pub fn appendCode(self: *ELFWriter, bytes: []const u8) !void {
        try self.code.appendSlice(self.allocator, bytes);
    }
    
    pub fn appendData(self: *ELFWriter, bytes: []const u8) !u64 {
        const offset = self.data.items.len;
        try self.data.appendSlice(self.allocator, bytes);
        return @intCast(offset);
    }
    
    pub fn getCurrentOffset(self: *ELFWriter) u32 {
        return @intCast(self.code.items.len);
    }
    
    pub fn setEntryPoint(self: *ELFWriter, offset: u32) !void {
        self.entry_point = offset;
    }
    
    /// Write complete ELF file to disk
    pub fn writeToFile(self: *ELFWriter, io: std.Io, path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.createFile(io, path, .{});
        defer file.close(io);
        
        // Check if we need dynamic linking
        const has_dynamic = self.dynamic_symbols.items.len > 0;
        
        // ELF header constants
        const BASE_ADDRESS: u64 = 0x400000; // Standard Linux load address
        
        // Calculate offsets for segments
        var current_offset: u64 = 0x1000; // Start after header page
        
        // PT_INTERP data
        const interp_path = "/lib64/ld-linux-x86-64.so.2\x00";
        const interp_offset = if (has_dynamic) current_offset else 0;
        const interp_size = if (has_dynamic) interp_path.len else 0;
        if (has_dynamic) {
            current_offset += interp_size;
            current_offset = (current_offset + 7) & ~@as(u64, 7); // Align to 8 bytes
        }
        
        const code_offset = current_offset;
        const code_vaddr = BASE_ADDRESS + code_offset;
        const entry_vaddr = code_vaddr + self.entry_point;
        
        // Align data section to next page
        const code_size_aligned = (self.code.items.len + self.plt.items.len + 0xFFF) & ~@as(u64, 0xFFF);
        const data_offset = code_offset + code_size_aligned;
        const data_vaddr = BASE_ADDRESS + data_offset;
        
        // Count program headers
        var num_phdrs: u16 = 1; // At least PT_LOAD for code
        if (has_dynamic) num_phdrs += 1; // PT_INTERP
        if (self.data.items.len > 0 or has_dynamic) num_phdrs += 1; // PT_LOAD for data/GOT
        
        const empty_buffer = try self.allocator.alloc(u8, 0);
        var buffer = std.ArrayList(u8).fromOwnedSlice(empty_buffer);
        defer buffer.deinit(self.allocator);
        
        // ELF Header (64 bytes)
        try buffer.appendSlice(self.allocator, &[_]u8{
            0x7F, 'E', 'L', 'F',           // Magic number
            2,                              // 64-bit
            1,                              // Little endian
            1,                              // ELF version
            0,                              // System V ABI
            0, 0, 0, 0, 0, 0, 0, 0,        // Padding
        });
        
        const e_type: u16 = if (has_dynamic) 3 else 2; // ET_DYN for PIE, ET_EXEC otherwise
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(e_type));
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0x3E))); // e_machine: x86-64
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // e_version
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(entry_vaddr));   // e_entry
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 64))); // e_phoff: program header offset
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));  // e_shoff: no section headers
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 0)));  // e_flags
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 64))); // e_ehsize: ELF header size
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 56))); // e_phentsize: program header size
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(num_phdrs));    // e_phnum
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0)));  // e_shentsize
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0)));  // e_shnum
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0)));  // e_shstrndx
        
        // PT_INTERP if we have dynamic linking
        if (has_dynamic) {
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 3)));  // p_type: PT_INTERP
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 4)));  // p_flags: PF_R
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(interp_offset)); // p_offset
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(BASE_ADDRESS + interp_offset)); // p_vaddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(BASE_ADDRESS + interp_offset)); // p_paddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(interp_size));  // p_filesz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(interp_size));  // p_memsz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 1)));  // p_align
        }
        
        // Program Header: Code segment (PT_LOAD, executable)
        const total_code_size = self.code.items.len + self.plt.items.len;
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // p_type: PT_LOAD
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 5)));  // p_flags: PF_R | PF_X (readable + executable)
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(code_offset));   // p_offset
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(code_vaddr));    // p_vaddr
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(code_vaddr));    // p_paddr
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(total_code_size)); // p_filesz
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(total_code_size)); // p_memsz
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_align: 4KB page alignment
        
        // Program Header: Data segment (PT_LOAD, readable+writable)
        if (self.data.items.len > 0 or has_dynamic) {
            const total_data_size = self.got.items.len + self.data.items.len;
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // p_type: PT_LOAD
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 6)));  // p_flags: PF_R | PF_W (readable + writable)
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_offset));   // p_offset
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_vaddr));    // p_vaddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_vaddr));    // p_paddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(total_data_size)); // p_filesz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(total_data_size)); // p_memsz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_align: 4KB page alignment
        }
        
        // Pad to interp_offset if needed
        if (has_dynamic) {
            const current_size = buffer.items.len;
            const padding_needed = interp_offset - current_size;
            try buffer.appendNTimes(self.allocator, 0, padding_needed);
            
            // Write interpreter path
            try buffer.appendSlice(self.allocator, interp_path);
            
            // Pad to code_offset
            const after_interp = buffer.items.len;
            const code_padding = code_offset - after_interp;
            try buffer.appendNTimes(self.allocator, 0, code_padding);
        } else {
            // Pad to code_offset
            const current_size = buffer.items.len;
            const padding_needed = code_offset - current_size;
            try buffer.appendNTimes(self.allocator, 0, padding_needed);
        }
        
        // Append code + PLT
        try buffer.appendSlice(self.allocator, self.code.items);
        try buffer.appendSlice(self.allocator, self.plt.items);
        
        // Append GOT + data section if present
        if (self.data.items.len > 0 or has_dynamic) {
            // Pad to data_offset
            const current_size_after_code = buffer.items.len;
            const data_padding_needed = data_offset - current_size_after_code;
            try buffer.appendNTimes(self.allocator, 0, data_padding_needed);
            
            // Append GOT then data
            try buffer.appendSlice(self.allocator, self.got.items);
            try buffer.appendSlice(self.allocator, self.data.items);
        }
        
        // Write to file
        try file.writeStreamingAll(io, buffer.items);
    }
    
    /// Get the virtual address for a data offset
    pub fn getDataVAddr(self: *ELFWriter, data_offset: u64) u64 {
        const BASE_ADDRESS: u64 = 0x400000;
        const code_offset: u64 = 0x1000;
        const code_size_aligned = (self.code.items.len + 0xFFF) & ~@as(u64, 0xFFF);
        const data_section_offset = code_offset + code_size_aligned;
        return BASE_ADDRESS + data_section_offset + data_offset;
    }
};
