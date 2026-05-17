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
    dynsym: std.ArrayList(u8),
    dynstr: std.ArrayList(u8),
    hash: std.ArrayList(u8), // ELF hash table
    rela_plt: std.ArrayList(u8),
    dynamic: std.ArrayList(u8),
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
        const empty_dynsym = try allocator.alloc(u8, 0);
        const empty_dynstr = try allocator.alloc(u8, 0);
        const empty_hash = try allocator.alloc(u8, 0);
        const empty_rela_plt = try allocator.alloc(u8, 0);
        const empty_dynamic = try allocator.alloc(u8, 0);
        const empty_externs = try allocator.alloc(ExternSymbol, 0);
        const empty_dynsyms = try allocator.alloc(DynamicSymbol, 0);
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).fromOwnedSlice(empty_code),
            .data = std.ArrayList(u8).fromOwnedSlice(empty_data),
            .plt = std.ArrayList(u8).fromOwnedSlice(empty_plt),
            .got = std.ArrayList(u8).fromOwnedSlice(empty_got),
            .dynsym = std.ArrayList(u8).fromOwnedSlice(empty_dynsym),
            .dynstr = std.ArrayList(u8).fromOwnedSlice(empty_dynstr),
            .hash = std.ArrayList(u8).fromOwnedSlice(empty_hash),
            .rela_plt = std.ArrayList(u8).fromOwnedSlice(empty_rela_plt),
            .dynamic = std.ArrayList(u8).fromOwnedSlice(empty_dynamic),
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
        self.dynsym.deinit(self.allocator);
        self.dynstr.deinit(self.allocator);
        self.hash.deinit(self.allocator);
        self.rela_plt.deinit(self.allocator);
        self.dynamic.deinit(self.allocator);
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
    
    pub fn generatePLT(self: *ELFWriter, plt_base_addr: u64, got_base_addr: u64) !void {
        // PLT[0] - PLT header (16 bytes)
        const plt0_addr = plt_base_addr;
        
        // pushq GOT[1] - instruction: ff 35 [disp32]
        const push_opcode_size: u64 = 2;
        const push_disp_size: u64 = 4;
        const push_rip = plt0_addr + push_opcode_size + push_disp_size;
        const got1_addr = got_base_addr + 8;
        const got1_rel = @as(i32, @intCast(@as(i64, @intCast(got1_addr)) - @as(i64, @intCast(push_rip))));
        try self.plt.appendSlice(self.allocator, &[_]u8{ 0xFF, 0x35 });
        try self.plt.appendSlice(self.allocator, &std.mem.toBytes(got1_rel));
        
        // jmpq *GOT[2] - instruction: ff 25 [disp32]
        const jmp_offset_in_plt = push_opcode_size + push_disp_size;
        const jmp_opcode_size: u64 = 2;
        const jmp_disp_size: u64 = 4;
        const jmp_rip = plt0_addr + jmp_offset_in_plt + jmp_opcode_size + jmp_disp_size;
        const got2_addr = got_base_addr + 16;
        const got2_rel = @as(i32, @intCast(@as(i64, @intCast(got2_addr)) - @as(i64, @intCast(jmp_rip))));
        try self.plt.appendSlice(self.allocator, &[_]u8{ 0xFF, 0x25 });
        try self.plt.appendSlice(self.allocator, &std.mem.toBytes(got2_rel));
        
        // nopl 0x0(%rax) - 4 bytes padding
        try self.plt.appendSlice(self.allocator, &[_]u8{ 0x0F, 0x1F, 0x40, 0x00 });
        
        // Generate PLT entries for each dynamic symbol
        for (self.dynamic_symbols.items, 0..) |sym, i| {
            _ = sym;
            const plt_entry_addr = plt_base_addr + 16 + (i * 16);
            
            // PLT[i+1] - PLT entry (16 bytes each)
            // jmpq *GOT[i+3] - instruction: ff 25 [disp32]
            const entry_jmp_opcode_size: u64 = 2;
            const entry_jmp_disp_size: u64 = 4;
            const entry_jmp_rip = plt_entry_addr + entry_jmp_opcode_size + entry_jmp_disp_size;
            const got_entry_addr = got_base_addr + 24 + (i * 8);
            const got_rel = @as(i32, @intCast(@as(i64, @intCast(got_entry_addr)) - @as(i64, @intCast(entry_jmp_rip))));
            try self.plt.appendSlice(self.allocator, &[_]u8{ 0xFF, 0x25 });
            try self.plt.appendSlice(self.allocator, &std.mem.toBytes(got_rel));
            
            // pushq $index - instruction: 68 [imm32]
            try self.plt.appendSlice(self.allocator, &[_]u8{ 0x68 });
            try self.plt.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, @intCast(i))));
            
            // jmpq PLT[0] - instruction: e9 [disp32]
            const jmp_plt0_offset_in_entry: u64 = entry_jmp_opcode_size + entry_jmp_disp_size + 1 + 4; // jmp*GOT + push
            const jmp_plt0_opcode_size: u64 = 1;
            const jmp_plt0_disp_size: u64 = 4;
            const jmp_plt0_rip = plt_entry_addr + jmp_plt0_offset_in_entry + jmp_plt0_opcode_size + jmp_plt0_disp_size;
            const plt0_offset = @as(i32, @intCast(@as(i64, @intCast(plt0_addr)) - @as(i64, @intCast(jmp_plt0_rip))));
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
    
    pub fn generateDynStr(self: *ELFWriter) !std.StringHashMap(u32) {
        // Build dynamic string table
        // dynstr always starts with null byte
        try self.dynstr.append(self.allocator, 0);
        
        // Track string offsets
        var string_offsets = std.StringHashMap(u32).init(self.allocator);
        
        // Add libc.so.6
        const libc_offset: u32 = @intCast(self.dynstr.items.len);
        try string_offsets.put("libc.so.6", libc_offset);
        try self.dynstr.appendSlice(self.allocator, "libc.so.6\x00");
        
        // Add each dynamic symbol name
        for (self.dynamic_symbols.items) |sym| {
            const offset: u32 = @intCast(self.dynstr.items.len);
            try string_offsets.put(sym.name, offset);
            try self.dynstr.appendSlice(self.allocator, sym.name);
            try self.dynstr.append(self.allocator, 0);
        }
        
        return string_offsets;
    }
    
    pub fn generateDynSym(self: *ELFWriter, string_offsets: std.StringHashMap(u32)) !void {
        // Symbol table entry: 24 bytes each
        // First entry is always NULL symbol
        try self.dynsym.appendNTimes(self.allocator, 0, 24);
        
        // Add symbol for each external function
        for (self.dynamic_symbols.items) |sym| {
            const name_offset = string_offsets.get(sym.name) orelse 0;
            
            // st_name (offset in dynstr)
            try self.dynsym.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, name_offset)));
            
            // st_info: STB_GLOBAL << 4 | STT_FUNC = 0x12
            try self.dynsym.append(self.allocator, 0x12);
            
            // st_other: STV_DEFAULT = 0
            try self.dynsym.append(self.allocator, 0);
            
            // st_shndx: SHN_UNDEF = 0
            try self.dynsym.appendSlice(self.allocator, &std.mem.toBytes(@as(u16, 0)));
            
            // st_value: 0 for undefined symbols
            try self.dynsym.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));
            
            // st_size: 0 for undefined symbols
            try self.dynsym.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));
        }
    }
    
    /// ELF hash function (System V ABI)
    fn elfHash(name: []const u8) u32 {
        var h: u32 = 0;
        for (name) |c| {
            h = (h << 4) +% c;
            const g = h & 0xf0000000;
            if (g != 0) {
                h ^= g >> 24;
            }
            h &= ~g;
        }
        return h;
    }
    
    pub fn generateHash(self: *ELFWriter) !void {
        // ELF hash table structure:
        // u32 nbucket
        // u32 nchain
        // u32 bucket[nbucket]
        // u32 chain[nchain]
        
        const nsymbols = @as(u32, @intCast(self.dynamic_symbols.items.len + 1)); // +1 for NULL symbol
        const nbucket: u32 = nsymbols; // Simple: one bucket per symbol
        const nchain: u32 = nsymbols;
        
        // Header
        try self.hash.appendSlice(self.allocator, &std.mem.toBytes(nbucket));
        try self.hash.appendSlice(self.allocator, &std.mem.toBytes(nchain));
        
        // Build buckets array
        var buckets = try self.allocator.alloc(u32, nbucket);
        defer self.allocator.free(buckets);
        @memset(buckets, 0); // Initialize to 0 (STN_UNDEF)
        
        // Build chains array  
        var chains = try self.allocator.alloc(u32, nchain);
        defer self.allocator.free(chains);
        @memset(chains, 0); // Initialize to 0 (end of chain)
        
        // Hash each symbol (skip index 0 which is NULL)
        for (self.dynamic_symbols.items, 1..) |sym, sym_index| {
            const hash_val = elfHash(sym.name);
            const bucket_index = hash_val % nbucket;
            
            // Insert at head of chain
            chains[sym_index] = buckets[bucket_index];
            buckets[bucket_index] = @intCast(sym_index);
        }
        
        // Write buckets
        for (buckets) |bucket| {
            try self.hash.appendSlice(self.allocator, &std.mem.toBytes(bucket));
        }
        
        // Write chains
        for (chains) |chain| {
            try self.hash.appendSlice(self.allocator, &std.mem.toBytes(chain));
        }
    }
    
    pub fn generateRelaPlt(self: *ELFWriter, got_base_addr: u64) !void {
        // Relocation entry: 24 bytes each (Elf64_Rela)
        for (self.dynamic_symbols.items, 0..) |_, i| {
            // r_offset: address of GOT entry to patch
            const got_entry_addr = got_base_addr + 24 + (i * 8);
            try self.rela_plt.appendSlice(self.allocator, &std.mem.toBytes(got_entry_addr));
            
            // r_info: (symbol_index << 32) | R_X86_64_JUMP_SLOT (7)
            const sym_index: u64 = i + 1; // +1 because dynsym[0] is NULL
            const r_info: u64 = (sym_index << 32) | 7;
            try self.rela_plt.appendSlice(self.allocator, &std.mem.toBytes(r_info));
            
            // r_addend: 0
            try self.rela_plt.appendSlice(self.allocator, &std.mem.toBytes(@as(i64, 0)));
        }
    }
    
    pub fn generateDynamic(self: *ELFWriter, hash_addr: u64, dynsym_addr: u64, dynstr_addr: u64, rela_plt_addr: u64, got_addr: u64, string_offsets: std.StringHashMap(u32)) !void {
        // Dynamic entry: 16 bytes each (Elf64_Dyn)
        // Each entry is (d_tag: i64, d_val: u64)
        
        const DT_NULL: i64 = 0;
        const DT_NEEDED: i64 = 1;
        const DT_HASH: i64 = 4;
        const DT_STRTAB: i64 = 5;
        const DT_SYMTAB: i64 = 6;
        const DT_STRSZ: i64 = 10;
        const DT_SYMENT: i64 = 11;
        const DT_DEBUG: i64 = 21;
        const DT_PLTGOT: i64 = 3;
        const DT_PLTRELSZ: i64 = 2;
        const DT_PLTREL: i64 = 20;
        const DT_JMPREL: i64 = 23;
        const DT_RELA: i64 = 7;
        const DT_RELASZ: i64 = 8;
        const DT_RELAENT: i64 = 9;
        
        // DT_NEEDED: libc.so.6
        const libc_offset = string_offsets.get("libc.so.6") orelse 0;
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_NEEDED));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, libc_offset)));
        
        // DT_HASH: address of hash table
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_HASH));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(hash_addr));
        
        // DT_STRTAB: address of dynstr
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_STRTAB));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(dynstr_addr));
        
        // DT_SYMTAB: address of dynsym
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_SYMTAB));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(dynsym_addr));
        
        // DT_STRSZ: size of dynstr
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_STRSZ));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.dynstr.items.len)));
        
        // DT_SYMENT: size of symbol entry (24 bytes)
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_SYMENT));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 24)));
        
        // DT_DEBUG: reserved for debugger use (set to 0, filled by dynamic linker)
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_DEBUG));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));
        
        // DT_PLTGOT: address of GOT
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_PLTGOT));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(got_addr));
        
        // DT_JMPREL: address of .rela.plt
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_JMPREL));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(rela_plt_addr));
        
        // DT_PLTRELSZ: size of .rela.plt
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_PLTRELSZ));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.rela_plt.items.len)));
        
        // DT_PLTREL: type of relocation (DT_RELA = 7)
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_PLTREL));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 7)));
        
        // DT_RELA: address of rela (same as JMPREL for now)
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_RELA));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(rela_plt_addr));
        
        // DT_RELASZ: size of rela
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_RELASZ));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.rela_plt.items.len)));
        
        // DT_RELAENT: size of rela entry (24 bytes)
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_RELAENT));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 24)));
        
        // DT_NULL: end of dynamic section
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(DT_NULL));
        try self.dynamic.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));
    }
    
    pub fn appendCode(self: *ELFWriter, bytes: []const u8) !void {
        try self.code.appendSlice(self.allocator, bytes);
    }
    
    pub fn appendData(self: *ELFWriter, bytes: []const u8) !u64 {
        const offset = self.data.items.len;
        try self.data.appendSlice(self.allocator, bytes);
        // Add null terminator for strings
        try self.data.append(self.allocator, 0);
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
        
        // Convert extern symbols to dynamic symbols
        // For now, we use placeholder offsets; they'll be calculated properly when generating PLT/GOT
        for (self.extern_symbols.items) |extern_sym| {
            try self.addDynamicSymbol(extern_sym.name, 0, 0);
        }
        
        // Check if we need dynamic linking
        const has_dynamic = self.dynamic_symbols.items.len > 0;
        
        // ELF header constants
        const BASE_ADDRESS: u64 = 0x400000; // Standard Linux load address
        
        // For dynamic linking, we need to generate sections early to know their sizes
        // We'll use placeholder addresses and fix them up later
        
        if (has_dynamic) {
            // Generate hash table
            try self.generateHash();
            
            // Generate dynstr and get string offsets
            var temp_string_offsets = try self.generateDynStr();
            defer temp_string_offsets.deinit();
            
            // Generate dynsym
            try self.generateDynSym(temp_string_offsets);
            
            // Generate rela.plt with placeholder GOT
            try self.generateRelaPlt(0xDEADBEEF);
            
            // Generate dynamic section with placeholder addresses
            // This is just to get the size; we'll regenerate with correct addresses later
            try self.generateDynamic(0, 0, 0, 0, 0, temp_string_offsets);
        }
        
        // Calculate offsets for all segments/sections
        var current_offset: u64 = 0x1000; // Start after header page
        
        // PT_INTERP data
        const interp_path = "/lib64/ld-linux-x86-64.so.2\x00";
        const interp_offset = if (has_dynamic) current_offset else 0;
        const interp_size = if (has_dynamic) interp_path.len else 0;
        if (has_dynamic) {
            current_offset += interp_size;
            current_offset = (current_offset + 7) & ~@as(u64, 7); // Align to 8 bytes
        }
        
        // Dynamic sections (read-only)
        const hash_offset = if (has_dynamic) current_offset else 0;
        const hash_addr = BASE_ADDRESS + hash_offset;
        if (has_dynamic) {
            current_offset += self.hash.items.len;
            current_offset = (current_offset + 7) & ~@as(u64, 7);
        }
        
        const dynsym_offset = if (has_dynamic) current_offset else 0;
        const dynsym_addr = BASE_ADDRESS + dynsym_offset;
        if (has_dynamic) {
            current_offset += self.dynsym.items.len;
            current_offset = (current_offset + 7) & ~@as(u64, 7);
        }
        
        const dynstr_offset = if (has_dynamic) current_offset else 0;
        const dynstr_addr = BASE_ADDRESS + dynstr_offset;
        if (has_dynamic) {
            current_offset += self.dynstr.items.len;
            current_offset = (current_offset + 7) & ~@as(u64, 7);
        }
        
        const rela_plt_offset = if (has_dynamic) current_offset else 0;
        const rela_plt_addr = BASE_ADDRESS + rela_plt_offset;
        if (has_dynamic) {
            current_offset += self.rela_plt.items.len;
            current_offset = (current_offset + 7) & ~@as(u64, 7);
        }
        
        // Code section (align to page boundary for separate LOAD segment)
        current_offset = (current_offset + 0xFFF) & ~@as(u64, 0xFFF); // Align to 4KB page
        const code_offset = current_offset;
        const code_vaddr = BASE_ADDRESS + code_offset;
        const entry_vaddr = code_vaddr + self.entry_point;
        
        // Calculate sizes
        const code_size = self.code.items.len;
        
        // Put data at fixed offset 0x10000 to match getDataVAddr
        const data_offset: u64 = 0x10000;
        
        // Calculate data section size
        // IMPORTANT: These sizes must match the conservative estimates in getDataVAddr!
        const dynamic_size: u64 = 16 * 15;  // Fixed size, matches getDataVAddr
        const got_size: u64 = (3 + 10) * 8;  // Fixed size, matches getDataVAddr
        const string_data_size: u64 = self.data.items.len;
        const dynamic_addr = BASE_ADDRESS + data_offset;
        const got_addr = dynamic_addr + dynamic_size;
        
        const data_size = dynamic_size + got_size + string_data_size;
        const data_vaddr = BASE_ADDRESS + data_offset;
        
        // Calculate PLT address
        const plt_addr = BASE_ADDRESS + code_offset + code_size;
        
        // Now generate PLT and GOT with correct addresses
        if (has_dynamic) {
            try self.generatePLT(plt_addr, got_addr);
            try self.generateGOT(dynamic_addr, plt_addr);
            
            // Patch extern call sites to point to their PLT entries
            for (self.extern_symbols.items, 0..) |extern_sym, i| {
                // Find the PLT entry for this symbol
                const plt_entry_offset: u32 = 16 + @as(u32, @intCast(i)) * 16; // PLT[0] is 16 bytes, then 16 bytes per entry
                const plt_entry_addr = plt_addr + plt_entry_offset;
                
                // Calculate the relative offset from the call site
                // call_site_offset points to the displacement (after E8 opcode), so subtract 1 to get start of instruction
                const call_site_addr = BASE_ADDRESS + code_offset + extern_sym.call_site_offset - 1;
                const next_instr_addr = call_site_addr + 5; // call instruction is 5 bytes (e8 + 4-byte offset)
                const relative_offset: i32 = @intCast(plt_entry_addr - next_instr_addr);
                
                // Patch the call instruction in the code buffer
                // call_site_offset already points to the displacement (after the E8 opcode)
                std.mem.writeInt(i32, self.code.items[extern_sym.call_site_offset..][0..4], relative_offset, .little);
            }
        }
        
        // Now fix up .rela.plt and .dynamic section with correct addresses
        if (has_dynamic) {
            // Fix up rela.plt relocations with correct GOT address
            for (self.dynamic_symbols.items, 0..) |_, i| {
                const got_entry_addr = got_addr + 24 + (i * 8);
                const reloc_offset = i * 24; // Each relocation is 24 bytes
                // Overwrite r_offset field (first 8 bytes of relocation)
                std.mem.writeInt(u64, self.rela_plt.items[reloc_offset..][0..8], got_entry_addr, .little);
            }
            
            // Clear and regenerate dynamic section with correct addresses
            self.dynamic.clearRetainingCapacity();
            
            // Rebuild string offsets
            var temp_string_offsets = std.StringHashMap(u32).init(self.allocator);
            defer temp_string_offsets.deinit();
            var offset: u32 = 1; // Start after null byte
            try temp_string_offsets.put("libc.so.6", offset);
            offset += @intCast("libc.so.6\x00".len);
            
            for (self.dynamic_symbols.items) |sym| {
                try temp_string_offsets.put(sym.name, offset);
                offset += @intCast(sym.name.len + 1);
            }
            
            try self.generateDynamic(hash_addr, dynsym_addr, dynstr_addr, rela_plt_addr, got_addr, temp_string_offsets);
        }
        
        // Count program headers
        var num_phdrs: u16 = 2; // PT_LOAD for headers + PT_LOAD for code
        if (has_dynamic) num_phdrs += 3; // PT_LOAD (ro data) + PT_INTERP + PT_DYNAMIC
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
        
        const e_type: u16 = 2; // Always ET_EXEC for now (not PIE)
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
        
        // PT_LOAD for ELF header and program headers (needed by dynamic linker)
        // This covers offset 0-0x1000 (the first page)
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // p_type: PT_LOAD
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 4)));  // p_flags: PF_R
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0)));  // p_offset
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(BASE_ADDRESS)); // p_vaddr
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(BASE_ADDRESS)); // p_paddr
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_filesz - whole first page
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_memsz
        try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_align: 4KB
        
        // PT_LOAD for read-only data (if we have dynamic linking)
        if (has_dynamic) {
            // This PT_LOAD covers INTERP, dynsym, dynstr, and rela.plt
            const ro_data_size = code_offset - interp_offset;
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // p_type: PT_LOAD
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 4)));  // p_flags: PF_R (read-only)
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(interp_offset)); // p_offset
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(BASE_ADDRESS + interp_offset)); // p_vaddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(BASE_ADDRESS + interp_offset)); // p_paddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(ro_data_size)); // p_filesz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(ro_data_size)); // p_memsz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_align: 4KB
        }
        
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
        
        // PT_DYNAMIC if we have dynamic linking
        if (has_dynamic) {
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 2)));  // p_type: PT_DYNAMIC
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 6)));  // p_flags: PF_R | PF_W
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_offset)); // p_offset
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(dynamic_addr));  // p_vaddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(dynamic_addr));  // p_paddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.dynamic.items.len))); // p_filesz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, self.dynamic.items.len))); // p_memsz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 8)));  // p_align
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
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 1)));  // p_type: PT_LOAD
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u32, 6)));  // p_flags: PF_R | PF_W (readable + writable)
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_offset));   // p_offset
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_vaddr));    // p_vaddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_vaddr));    // p_paddr
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_size)); // p_filesz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(data_size)); // p_memsz
            try buffer.appendSlice(self.allocator, &std.mem.toBytes(@as(u64, 0x1000))); // p_align: 4KB page alignment
        }
        
        // Pad to interp_offset if needed
        if (has_dynamic) {
            const current_size = buffer.items.len;
            const padding_needed = interp_offset - current_size;
            try buffer.appendNTimes(self.allocator, 0, padding_needed);
            
            // Write interpreter path
            try buffer.appendSlice(self.allocator, interp_path);
            
            // Pad to hash_offset
            const after_interp = buffer.items.len;
            const hash_padding = hash_offset - after_interp;
            try buffer.appendNTimes(self.allocator, 0, hash_padding);
            
            // Write dynamic sections
            try buffer.appendSlice(self.allocator, self.hash.items);
            const after_hash = buffer.items.len;
            try buffer.appendNTimes(self.allocator, 0, dynsym_offset - after_hash);
            
            try buffer.appendSlice(self.allocator, self.dynsym.items);
            const after_dynsym = buffer.items.len;
            try buffer.appendNTimes(self.allocator, 0, dynstr_offset - after_dynsym);
            
            try buffer.appendSlice(self.allocator, self.dynstr.items);
            const after_dynstr = buffer.items.len;
            try buffer.appendNTimes(self.allocator, 0, rela_plt_offset - after_dynstr);
            
            try buffer.appendSlice(self.allocator, self.rela_plt.items);
            const after_rela = buffer.items.len;
            try buffer.appendNTimes(self.allocator, 0, code_offset - after_rela);
        } else {
            // Pad to code_offset
            const current_size = buffer.items.len;
            const padding_needed = code_offset - current_size;
            try buffer.appendNTimes(self.allocator, 0, padding_needed);
        }
        
        // Append code + PLT
        try buffer.appendSlice(self.allocator, self.code.items);
        try buffer.appendSlice(self.allocator, self.plt.items);
        
        // Append dynamic + GOT + data section if present
        if (self.data.items.len > 0 or has_dynamic) {
            // Pad to data_offset
            const current_size_after_code = buffer.items.len;
            const data_padding_needed = data_offset - current_size_after_code;
            try buffer.appendNTimes(self.allocator, 0, data_padding_needed);
            
            // Append dynamic, GOT, then data
            if (has_dynamic) {
                // Write actual dynamic section
                try buffer.appendSlice(self.allocator, self.dynamic.items);
                // Pad to fixed dynamic_size (must match getDataVAddr)
                const actual_dynamic_size = self.dynamic.items.len;
                if (actual_dynamic_size < dynamic_size) {
                    try buffer.appendNTimes(self.allocator, 0, dynamic_size - actual_dynamic_size);
                }
                
                // Write actual GOT
                try buffer.appendSlice(self.allocator, self.got.items);
                // Pad to fixed got_size (must match getDataVAddr)
                const actual_got_size = self.got.items.len;
                if (actual_got_size < got_size) {
                    try buffer.appendNTimes(self.allocator, 0, got_size - actual_got_size);
                }
            }
            try buffer.appendSlice(self.allocator, self.data.items);
        }
        
        // Write to file
        try file.writeStreamingAll(io, buffer.items);
    }
    
    /// Get the virtual address for a data offset
    pub fn getDataVAddr(self: *ELFWriter, data_offset: u64) u64 {
        const BASE_ADDRESS: u64 = 0x400000;
        
        // Simple approach: put data at a fixed offset that's guaranteed to be after everything else
        // Code + PLT will never exceed 0x10000 (64KB), and dynamic sections are small
        // So we can safely put data at BASE + 0x10000
        const DATA_BASE = BASE_ADDRESS + 0x10000;  // 0x410000
        
        // ALWAYS account for dynamic and GOT sections that are written before user data
        // We use conservative fixed estimates because this is called during codegen,
        // before extern_symbols is populated. The actual layout in writeToFile MUST match!
        const dynamic_size: u64 = 16 * 15;  // ~15 dynamic entries (conservative)
        const got_size: u64 = (3 + 10) * 8;  // 3 reserved + up to 10 symbols (conservative)
        
        _ = self;
        
        return DATA_BASE + dynamic_size + got_size + data_offset;
    }
};
