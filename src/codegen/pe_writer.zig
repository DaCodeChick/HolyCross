const std = @import("std");
const Allocator = std.mem.Allocator;

/// PE32+ (Portable Executable) Writer for Windows x64
/// Generates .exe files for Windows x64 (both MSVC and MinGW compatible)
pub const PEWriter = struct {
    allocator: Allocator,
    
    // Code and data sections
    code: std.ArrayList(u8),
    rdata: std.ArrayList(u8),  // Read-only data (strings, constants)
    data: std.ArrayList(u8),   // Initialized data
    
    // Import information
    imports: std.ArrayList(ImportedDLL),
    
    // Entry point
    entry_point_offset: u32,
    
    // Base addresses
    image_base: u64,  // Preferred load address
    code_base: u32,   // RVA of .text section
    
    pub const ImportedDLL = struct {
        name: []const u8,
        functions: std.ArrayList(ImportedFunction),
        
        pub const ImportedFunction = struct {
            name: []const u8,
            hint: u16,  // Index hint for faster lookup
        };
    };
    
    pub fn init(allocator: Allocator) !PEWriter {
        const empty_code = try allocator.alloc(u8, 0);
        const empty_rdata = try allocator.alloc(u8, 0);
        const empty_data = try allocator.alloc(u8, 0);
        const empty_imports = try allocator.alloc(ImportedDLL, 0);
        
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).fromOwnedSlice(empty_code),
            .rdata = std.ArrayList(u8).fromOwnedSlice(empty_rdata),
            .data = std.ArrayList(u8).fromOwnedSlice(empty_data),
            .imports = std.ArrayList(ImportedDLL).fromOwnedSlice(empty_imports),
            .entry_point_offset = 0,
            .image_base = 0x140000000,  // Standard Windows x64 image base
            .code_base = 0x1000,         // .text starts at 4KB (after headers)
        };
    }
    
    pub fn deinit(self: *PEWriter) void {
        self.code.deinit(self.allocator);
        self.rdata.deinit(self.allocator);
        self.data.deinit(self.allocator);
        
        for (self.imports.items) |*dll| {
            for (dll.functions.items) |func| {
                self.allocator.free(func.name);
            }
            dll.functions.deinit(self.allocator);
            self.allocator.free(dll.name);
        }
        self.imports.deinit(self.allocator);
    }
    
    /// Add machine code to .text section
    pub fn addCode(self: *PEWriter, code: []const u8) !void {
        try self.code.appendSlice(self.allocator, code);
    }
    
    /// Compatibility wrapper for appendCode (used by CodeBuffer)
    pub fn appendCode(self: *PEWriter, code: []const u8) !void {
        try self.addCode(code);
    }
    
    /// Compatibility wrapper for appendData (used by CodeBuffer)
    pub fn appendData(self: *PEWriter, bytes: []const u8) !u64 {
        const offset = self.data.items.len;
        try self.addData(bytes);
        return @intCast(offset);
    }
    
    /// Get data virtual address for a given offset
    pub fn getDataVAddr(self: *PEWriter, data_offset: u64) u64 {
        // RVA of .data section = code_base + aligned code size + aligned rdata size
        const code_aligned = self.alignUp(self.code.items.len, 0x1000);
        const rdata_aligned = self.alignUp(self.rdata.items.len, 0x1000);
        const data_rva = self.code_base + code_aligned + rdata_aligned;
        return self.image_base + data_rva + data_offset;
    }
    
    /// Add read-only data (string literals, constants)
    pub fn addReadOnlyData(self: *PEWriter, data: []const u8) !void {
        try self.rdata.appendSlice(self.allocator, data);
    }
    
    /// Add initialized data
    pub fn addData(self: *PEWriter, data: []const u8) !void {
        try self.data.appendSlice(self.allocator, data);
    }
    
    /// Set the entry point RVA (relative to code section)
    pub fn setEntryPoint(self: *PEWriter, offset: u32) void {
        self.entry_point_offset = offset;
    }
    
    /// Add an imported DLL with its functions
    pub fn addImport(self: *PEWriter, dll_name: []const u8, functions: []const []const u8) !void {
        const empty_funcs = try self.allocator.alloc(ImportedDLL.ImportedFunction, 0);
        var func_list = std.ArrayList(ImportedDLL.ImportedFunction).fromOwnedSlice(empty_funcs);
        
        for (functions, 0..) |func_name, idx| {
            try func_list.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, func_name),
                .hint = @intCast(idx),
            });
        }
        
        try self.imports.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, dll_name),
            .functions = func_list,
        });
    }
    
    /// Write PE32+ executable to file
    pub fn writeToFile(self: *PEWriter, io: std.Io, path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.createFile(io, path, .{});
        defer file.close(io);
        
        var write_buffer: [8192]u8 = undefined;
        var buffered_writer = file.writer(io, &write_buffer);
        defer buffered_writer.flush() catch {};
        
        try self.write(&buffered_writer.interface);
    }
    
    /// Write PE32+ executable to a Writer interface
    pub fn write(self: *PEWriter, writer: *std.Io.Writer) !void {
        // Alignment constants
        const file_alignment: u32 = 0x200;   // 512 bytes
        const section_alignment: u32 = 0x1000; // 4KB
        
        // Calculate section sizes (aligned)
        const code_size = self.alignUp(self.code.items.len, file_alignment);
        const rdata_size = self.alignUp(self.rdata.items.len, file_alignment);
        const data_size = self.alignUp(self.data.items.len, file_alignment);
        
        // Calculate import directory size (rough estimate)
        const import_size = self.calculateImportSize();
        const idata_size = self.alignUp(import_size, file_alignment);
        
        // Calculate RVAs (Relative Virtual Addresses)
        const code_rva = section_alignment;  // .text at 0x1000
        const rdata_rva = code_rva + self.alignUp(self.code.items.len, section_alignment);
        const data_rva = rdata_rva + self.alignUp(self.rdata.items.len, section_alignment);
        const idata_rva = data_rva + self.alignUp(self.data.items.len, section_alignment);
        
        // Calculate file offsets
        const headers_size = self.alignUp(self.calculateHeadersSize(), file_alignment);
        const code_offset = headers_size;
        const rdata_offset = code_offset + code_size;
        const data_offset = rdata_offset + rdata_size;
        const idata_offset = data_offset + data_size;
        
        // Calculate total image size
        const image_size = idata_rva + self.alignUp(import_size, section_alignment);
        
        // Write DOS header and stub
        try self.writeDOSHeader(writer);
        try self.writeDOSStub(writer);
        
        // Write PE signature
        try writer.writeAll("PE\x00\x00");
        
        // Write COFF file header
        try self.writeCOFFHeader(writer, 4); // 4 sections: .text, .rdata, .data, .idata
        
        // Write optional header (PE32+)
        try self.writeOptionalHeader(writer, code_rva + self.entry_point_offset, 
            code_size, rdata_size + data_size + idata_size, image_size,
            headers_size, idata_rva, import_size);
        
        // Write section headers
        try self.writeSectionHeader(writer, ".text", code_size, code_rva, code_size, code_offset,
            0x60000020); // CODE | EXECUTE | READ
        try self.writeSectionHeader(writer, ".rdata", rdata_size, rdata_rva, rdata_size, rdata_offset,
            0x40000040); // INITIALIZED_DATA | READ
        try self.writeSectionHeader(writer, ".data", data_size, data_rva, data_size, data_offset,
            0xC0000040); // INITIALIZED_DATA | READ | WRITE
        try self.writeSectionHeader(writer, ".idata", idata_size, idata_rva, idata_size, idata_offset,
            0x40000040); // INITIALIZED_DATA | READ
        
        // Pad to file alignment
        try self.writePadding(writer, headers_size - self.calculateHeadersSize());
        
        // Write section data
        try writer.writeAll(self.code.items);
        try self.writePadding(writer, @as(u32, @intCast(code_size - self.code.items.len)));
        
        try writer.writeAll(self.rdata.items);
        try self.writePadding(writer, @as(u32, @intCast(rdata_size - self.rdata.items.len)));
        
        try writer.writeAll(self.data.items);
        try self.writePadding(writer, @as(u32, @intCast(data_size - self.data.items.len)));
        
        // Write import directory
        try self.writeImportDirectory(writer, idata_rva);
        try self.writePadding(writer, @as(u32, @intCast(idata_size - import_size)));
    }
    
    fn writeDOSHeader(self: *PEWriter, writer: *std.Io.Writer) !void {
        _ = self;
        // DOS header (64 bytes)
        try writer.writeInt(u16, 0x5A4D, .little); // e_magic: "MZ"
        try writer.writeInt(u16, 0x90, .little);   // e_cblp
        try writer.writeInt(u16, 0x03, .little);   // e_cp
        try writer.writeInt(u16, 0x00, .little);   // e_crlc
        try writer.writeInt(u16, 0x04, .little);   // e_cparhdr
        try writer.writeInt(u16, 0x00, .little);   // e_minalloc
        try writer.writeInt(u16, 0xFFFF, .little); // e_maxalloc
        try writer.writeInt(u16, 0x00, .little);   // e_ss
        try writer.writeInt(u16, 0xB8, .little);   // e_sp
        try writer.writeInt(u16, 0x00, .little);   // e_csum
        try writer.writeInt(u16, 0x00, .little);   // e_ip
        try writer.writeInt(u16, 0x00, .little);   // e_cs
        try writer.writeInt(u16, 0x40, .little);   // e_lfarlc
        try writer.writeInt(u16, 0x00, .little);   // e_ovno
        try writer.writeInt(u64, 0, .little);      // e_res[4]
        try writer.writeInt(u16, 0x00, .little);   // e_oemid
        try writer.writeInt(u16, 0x00, .little);   // e_oeminfo
        try writer.writeInt(u64, 0, .little);      // e_res2[10] (part 1)
        try writer.writeInt(u64, 0, .little);      // e_res2[10] (part 2)
        try writer.writeInt(u32, 0, .little);      // e_res2[10] (part 3)
        try writer.writeInt(u32, 0x80, .little);   // e_lfanew: PE header at offset 0x80
    }
    
    fn writeDOSStub(self: *PEWriter, writer: *std.Io.Writer) !void {
        _ = self;
        // Simple DOS stub program that prints "This program cannot be run in DOS mode."
        const dos_stub = [_]u8{
            0x0E, 0x1F, 0xBA, 0x0E, 0x00, 0xB4, 0x09, 0xCD,
            0x21, 0xB8, 0x01, 0x4C, 0xCD, 0x21, 0x54, 0x68,
            0x69, 0x73, 0x20, 0x70, 0x72, 0x6F, 0x67, 0x72,
            0x61, 0x6D, 0x20, 0x63, 0x61, 0x6E, 0x6E, 0x6F,
            0x74, 0x20, 0x62, 0x65, 0x20, 0x72, 0x75, 0x6E,
            0x20, 0x69, 0x6E, 0x20, 0x44, 0x4F, 0x53, 0x20,
            0x6D, 0x6F, 0x64, 0x65, 0x2E, 0x0D, 0x0D, 0x0A,
            0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        };
        try writer.writeAll(&dos_stub);
        // Pad to 0x80 (128 bytes total: 64 DOS header + 64 stub)
    }
    
    fn writeCOFFHeader(self: *PEWriter, writer: *std.Io.Writer, section_count: u16) !void {
        _ = self;
        try writer.writeInt(u16, 0x8664, .little);  // Machine: AMD64
        try writer.writeInt(u16, section_count, .little);
        try writer.writeInt(u32, 0, .little); // Timestamp (0 for deterministic builds)
        try writer.writeInt(u32, 0, .little);       // PointerToSymbolTable (deprecated)
        try writer.writeInt(u32, 0, .little);       // NumberOfSymbols (deprecated)
        try writer.writeInt(u16, 240, .little);     // SizeOfOptionalHeader (PE32+)
        try writer.writeInt(u16, 0x0022, .little);  // Characteristics: EXECUTABLE | LARGE_ADDRESS_AWARE
    }
    
    fn writeOptionalHeader(self: *PEWriter, writer: *std.Io.Writer, entry_point: u32,
                           code_size: u32, data_size: u32, image_size: u32,
                           headers_size: u32, import_rva: u32, import_size: u32) !void {
        // Standard fields
        try writer.writeInt(u16, 0x020B, .little);  // Magic: PE32+
        try writer.writeInt(u8, 14, .little);       // MajorLinkerVersion
        try writer.writeInt(u8, 0, .little);        // MinorLinkerVersion
        try writer.writeInt(u32, code_size, .little);
        try writer.writeInt(u32, data_size, .little);
        try writer.writeInt(u32, 0, .little);       // SizeOfUninitializedData
        try writer.writeInt(u32, entry_point, .little);
        try writer.writeInt(u32, 0x1000, .little);  // BaseOfCode
        
        // Windows-specific fields
        try writer.writeInt(u64, self.image_base, .little);
        try writer.writeInt(u32, 0x1000, .little);  // SectionAlignment
        try writer.writeInt(u32, 0x200, .little);   // FileAlignment
        try writer.writeInt(u16, 6, .little);       // MajorOperatingSystemVersion
        try writer.writeInt(u16, 0, .little);       // MinorOperatingSystemVersion
        try writer.writeInt(u16, 0, .little);       // MajorImageVersion
        try writer.writeInt(u16, 0, .little);       // MinorImageVersion
        try writer.writeInt(u16, 6, .little);       // MajorSubsystemVersion
        try writer.writeInt(u16, 0, .little);       // MinorSubsystemVersion
        try writer.writeInt(u32, 0, .little);       // Win32VersionValue
        try writer.writeInt(u32, image_size, .little);
        try writer.writeInt(u32, headers_size, .little);
        try writer.writeInt(u32, 0, .little);       // CheckSum (can be 0 for non-drivers)
        try writer.writeInt(u16, 3, .little);       // Subsystem: CONSOLE
        try writer.writeInt(u16, 0x8160, .little);  // DllCharacteristics: NX_COMPAT | DYNAMIC_BASE | TERMINAL_SERVER_AWARE
        try writer.writeInt(u64, 0x100000, .little); // SizeOfStackReserve (1MB)
        try writer.writeInt(u64, 0x1000, .little);   // SizeOfStackCommit (4KB)
        try writer.writeInt(u64, 0x100000, .little); // SizeOfHeapReserve (1MB)
        try writer.writeInt(u64, 0x1000, .little);   // SizeOfHeapCommit (4KB)
        try writer.writeInt(u32, 0, .little);        // LoaderFlags
        try writer.writeInt(u32, 16, .little);       // NumberOfRvaAndSizes
        
        // Data directories (16 entries)
        // 0: Export Directory
        try writer.writeInt(u64, 0, .little);
        // 1: Import Directory
        try writer.writeInt(u32, import_rva, .little);
        try writer.writeInt(u32, import_size, .little);
        // 2-15: Other directories (all zeros for now)
        var i: usize = 2;
        while (i < 16) : (i += 1) {
            try writer.writeInt(u64, 0, .little);
        }
    }
    
    fn writeSectionHeader(self: *PEWriter, writer: *std.Io.Writer, name: []const u8,
                          virtual_size: u32, virtual_address: u32, raw_size: u32,
                          raw_offset: u32, characteristics: u32) !void {
        _ = self;
        // Name (8 bytes, null-padded)
        var name_bytes: [8]u8 = [_]u8{0} ** 8;
        @memcpy(name_bytes[0..@min(name.len, 8)], name[0..@min(name.len, 8)]);
        try writer.writeAll(&name_bytes);
        
        try writer.writeInt(u32, virtual_size, .little);
        try writer.writeInt(u32, virtual_address, .little);
        try writer.writeInt(u32, raw_size, .little);
        try writer.writeInt(u32, raw_offset, .little);
        try writer.writeInt(u32, 0, .little);  // PointerToRelocations
        try writer.writeInt(u32, 0, .little);  // PointerToLinenumbers
        try writer.writeInt(u16, 0, .little);  // NumberOfRelocations
        try writer.writeInt(u16, 0, .little);  // NumberOfLinenumbers
        try writer.writeInt(u32, characteristics, .little);
    }
    
    fn writeImportDirectory(self: *PEWriter, writer: *std.Io.Writer, base_rva: u32) !void {
        if (self.imports.items.len == 0) {
            // No imports - just write null descriptor
            try writer.writeInt(u64, 0, .little);
            try writer.writeInt(u64, 0, .little);
            try writer.writeInt(u32, 0, .little);
            return;
        }
        
        // Calculate offsets within .idata section
        const descriptor_size = 20; // IMAGE_IMPORT_DESCRIPTOR size
        const descriptors_size = (@as(u32, @intCast(self.imports.items.len)) + 1) * descriptor_size; // +1 for null terminator
        
        var offset = descriptors_size;
        
        // Build Import Lookup Table (ILT) and Import Address Table (IAT)
        const empty_dll_data = try self.allocator.alloc(DLLImportData, 0);
        var dll_data: std.ArrayList(DLLImportData) = std.ArrayList(DLLImportData).fromOwnedSlice(empty_dll_data);
        defer {
            for (dll_data.items) |*data| {
                data.ilt.deinit(self.allocator);
                data.iat.deinit(self.allocator);
            }
            dll_data.deinit(self.allocator);
        }
        
        for (self.imports.items) |dll| {
            const empty_ilt = try self.allocator.alloc(u64, 0);
            const empty_iat = try self.allocator.alloc(u64, 0);
            
            var ilt = std.ArrayList(u64).fromOwnedSlice(empty_ilt);
            var iat = std.ArrayList(u64).fromOwnedSlice(empty_iat);
            
            const name_table_offset = offset;
            var names_size: u32 = 0;
            
            for (dll.functions.items) |func| {
                // Each name entry: 2 bytes hint + name + null terminator
                const entry_size = 2 + @as(u32, @intCast(func.name.len)) + 1;
                const name_rva = base_rva + name_table_offset + names_size;
                
                try ilt.append(self.allocator, name_rva);
                try iat.append(self.allocator, name_rva);
                
                names_size += entry_size;
            }
            
            // Null terminator for ILT/IAT
            try ilt.append(self.allocator, 0);
            try iat.append(self.allocator, 0);
            
            // Align names size
            names_size = self.alignUp(names_size, 2);
            
            const ilt_offset = offset;
            const ilt_size = @as(u32, @intCast(ilt.items.len)) * 8; // 8 bytes per entry (PE32+)
            offset += ilt_size;
            
            const iat_offset = offset;
            const iat_size = @as(u32, @intCast(iat.items.len)) * 8;
            offset += iat_size;
            
            const dll_name_offset = offset;
            offset += @as(u32, @intCast(dll.name.len)) + 1;
            offset = self.alignUp(offset, 2);
            
            offset += names_size;
            
            try dll_data.append(self.allocator, .{
                .ilt = ilt,
                .iat = iat,
                .ilt_rva = base_rva + ilt_offset,
                .iat_rva = base_rva + iat_offset,
                .name_rva = base_rva + dll_name_offset,
                .names_offset = name_table_offset,
            });
        }
        
        // Write import descriptors
        for (dll_data.items, 0..) |data, idx| {
            try writer.writeInt(u32, data.ilt_rva, .little); // OriginalFirstThunk (ILT)
            try writer.writeInt(u32, 0, .little);             // TimeDateStamp
            try writer.writeInt(u32, 0, .little);             // ForwarderChain
            try writer.writeInt(u32, data.name_rva, .little); // Name
            try writer.writeInt(u32, data.iat_rva, .little);  // FirstThunk (IAT)
            
            _ = idx;
        }
        
        // Null descriptor
        try writer.writeInt(u64, 0, .little);
        try writer.writeInt(u64, 0, .little);
        try writer.writeInt(u32, 0, .little);
        
        // Write ILTs, IATs, DLL names, and function names
        for (dll_data.items, 0..) |data, dll_idx| {
            // Write ILT
            for (data.ilt.items) |entry| {
                try writer.writeInt(u64, entry, .little);
            }
            
            // Write IAT
            for (data.iat.items) |entry| {
                try writer.writeInt(u64, entry, .little);
            }
            
            // Write DLL name
            const dll = self.imports.items[dll_idx];
            try writer.writeAll(dll.name);
            try writer.writeInt(u8, 0, .little); // Null terminator
            
            // Align to 2 bytes
            const dll_name_size = dll.name.len + 1;
            const dll_padding = self.alignUp(dll_name_size, 2) - @as(u32, @intCast(dll_name_size));
            var p: u32 = 0;
            while (p < dll_padding) : (p += 1) {
                try writer.writeInt(u8, 0, .little);
            }
            
            // Write function names (hint + name)
            for (dll.functions.items) |func| {
                try writer.writeInt(u16, func.hint, .little);
                try writer.writeAll(func.name);
                try writer.writeInt(u8, 0, .little); // Null terminator
            }
            
            // Align names section
            const funcs_size: u32 = blk: {
                var size: u32 = 0;
                for (dll.functions.items) |func| {
                    size += 2 + @as(u32, @intCast(func.name.len)) + 1;
                }
                break :blk size;
            };
            const names_padding = self.alignUp(funcs_size, 2) - funcs_size;
            p = 0;
            while (p < names_padding) : (p += 1) {
                try writer.writeInt(u8, 0, .little);
            }
        }
    }
    
    const DLLImportData = struct {
        ilt: std.ArrayList(u64),
        iat: std.ArrayList(u64),
        ilt_rva: u32,
        iat_rva: u32,
        name_rva: u32,
        names_offset: u32,
    };
    
    fn calculateImportSize(self: *PEWriter) u32 {
        if (self.imports.items.len == 0) {
            return 20; // Just null descriptor
        }
        
        const descriptor_size: u32 = 20;
        var size = (@as(u32, @intCast(self.imports.items.len)) + 1) * descriptor_size;
        
        for (self.imports.items) |dll| {
            // ILT and IAT: (num_functions + 1 null) * 8 bytes each
            const num_entries = (@as(u32, @intCast(dll.functions.items.len)) + 1) * 8;
            size += num_entries * 2; // ILT + IAT
            
            // DLL name
            size += @as(u32, @intCast(dll.name.len)) + 1;
            size = self.alignUp(size, 2);
            
            // Function names (hint + name + null)
            for (dll.functions.items) |func| {
                size += 2 + @as(u32, @intCast(func.name.len)) + 1;
            }
            size = self.alignUp(size, 2);
        }
        
        return size;
    }
    
    fn calculateHeadersSize(self: *PEWriter) u32 {
        _ = self;
        const dos_header = 64;
        const dos_stub = 64;
        const pe_signature = 4;
        const coff_header = 20;
        const optional_header = 240;
        const section_headers = 40 * 4; // 4 sections
        return dos_header + dos_stub + pe_signature + coff_header + optional_header + section_headers;
    }
    
    fn writePadding(self: *PEWriter, writer: *std.Io.Writer, size: u32) !void {
        _ = self;
        var i: u32 = 0;
        while (i < size) : (i += 1) {
            try writer.writeInt(u8, 0, .little);
        }
    }
    
    fn alignUp(self: *PEWriter, value: usize, alignment: u32) u32 {
        _ = self;
        const align_u64: u64 = @intCast(alignment);
        const val_u64: u64 = @intCast(value);
        const aligned = (val_u64 + align_u64 - 1) / align_u64 * align_u64;
        return @intCast(aligned);
    }
};
