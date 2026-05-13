const std = @import("std");
const Allocator = std.mem.Allocator;

/// ELF64 file writer for Linux x64 executables
/// Generates minimal ELF files with just code and data sections
pub const ELFWriter = struct {
    allocator: Allocator,
    code: std.ArrayList(u8),
    data: std.ArrayList(u8),
    entry_point: u32,
    
    pub fn init(allocator: Allocator) !ELFWriter {
        const empty_code = try allocator.alloc(u8, 0);
        const empty_data = try allocator.alloc(u8, 0);
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).fromOwnedSlice(empty_code),
            .data = std.ArrayList(u8).fromOwnedSlice(empty_data),
            .entry_point = 0,
        };
    }
    
    pub fn deinit(self: *ELFWriter) void {
        self.code.deinit(self.allocator);
        self.data.deinit(self.allocator);
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
        
        // ELF header constants
        const BASE_ADDRESS: u64 = 0x400000; // Standard Linux load address
        const code_offset: u64 = 0x1000; // Start code after header page
        const code_vaddr = BASE_ADDRESS + code_offset;
        const entry_vaddr = code_vaddr + self.entry_point;
        
        // Align data section to next page
        const code_size_aligned = (self.code.items.len + 0xFFF) & ~@as(u64, 0xFFF);
        const data_offset = code_offset + code_size_aligned;
        const data_vaddr = BASE_ADDRESS + data_offset;
        
        const num_phdrs: u16 = if (self.data.items.len > 0) 2 else 1;
        
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
        
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 2)));  // e_type: ET_EXEC
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
        
        // Program Header 1: Code segment (PT_LOAD, executable)
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // p_type: PT_LOAD
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 5)));  // p_flags: PF_R | PF_X (readable + executable)
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(code_offset));   // p_offset
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(code_vaddr));    // p_vaddr
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(code_vaddr));    // p_paddr
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.code.items.len))); // p_filesz
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.code.items.len))); // p_memsz
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_align: 4KB page alignment
        
        // Program Header 2: Data segment (PT_LOAD, readable+writable) - only if we have data
        if (self.data.items.len > 0) {
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // p_type: PT_LOAD
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 6)));  // p_flags: PF_R | PF_W (readable + writable)
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_offset));   // p_offset
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_vaddr));    // p_vaddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_vaddr));    // p_paddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.data.items.len))); // p_filesz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.data.items.len))); // p_memsz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_align: 4KB page alignment
        }
        
        // Pad to code_offset
        const current_size = buffer.items.len;
        const padding_needed = code_offset - current_size;
        try buffer.appendNTimes(self.allocator, 0, padding_needed);
        
        // Append code
        try buffer.appendSlice(self.allocator, self.code.items);
        
        // Append data section if present
        if (self.data.items.len > 0) {
            // Pad to data_offset
            const current_size_after_code = buffer.items.len;
            const data_padding_needed = data_offset - current_size_after_code;
            try buffer.appendNTimes(self.allocator, 0, data_padding_needed);
            
            // Append data
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
