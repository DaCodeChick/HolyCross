const std = @import("std");
const Allocator = std.mem.Allocator;

/// External Symbol Table - tracks imported functions and their call sites
/// Used for both PLT/GOT generation (Linux) and IAT stub generation (Windows)
pub const ExternalSymbolTable = struct {
    allocator: Allocator,
    symbols: std.StringHashMap(ExternalSymbol),
    
    pub fn init(allocator: Allocator) ExternalSymbolTable {
        return .{
            .allocator = allocator,
            .symbols = std.StringHashMap(ExternalSymbol).init(allocator),
        };
    }
    
    pub fn deinit(self: *ExternalSymbolTable) void {
        var iter = self.symbols.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.symbols.deinit();
    }
    
    /// Register an external function reference (call site)
    /// Records the call site offset for later patching/relocation
    pub fn addReference(self: *ExternalSymbolTable, func_name: []const u8, call_offset: u32, library_hint: ?[]const u8) !void {
        const gop = try self.symbols.getOrPut(func_name);
        
        if (!gop.found_existing) {
            // New symbol - initialize
            const name_copy = try self.allocator.dupe(u8, func_name);
            const lib_copy = if (library_hint) |lib| try self.allocator.dupe(u8, lib) else null;
            
            const empty_refs = try self.allocator.alloc(SymbolReference, 0);
            gop.value_ptr.* = .{
                .name = name_copy,
                .library_hint = lib_copy,
                .references = std.ArrayList(SymbolReference).fromOwnedSlice(empty_refs),
                .stub_offset = null,
                .got_iat_index = null,
            };
        }
        
        // Add reference
        try gop.value_ptr.references.append(self.allocator, .{
            .code_offset = call_offset,
        });
    }
    
    /// Assign a stub offset to an external symbol
    /// This is the address of the PLT entry (Linux) or jump stub (Windows)
    pub fn setStubOffset(self: *ExternalSymbolTable, func_name: []const u8, offset: u32) !void {
        if (self.symbols.getPtr(func_name)) |sym| {
            sym.stub_offset = offset;
        } else {
            return error.SymbolNotFound;
        }
    }
    
    /// Assign a GOT/IAT index to an external symbol
    pub fn setGotIatIndex(self: *ExternalSymbolTable, func_name: []const u8, index: u32) !void {
        if (self.symbols.getPtr(func_name)) |sym| {
            sym.got_iat_index = index;
        } else {
            return error.SymbolNotFound;
        }
    }
    
    /// Get symbol by name
    pub fn getSymbol(self: *const ExternalSymbolTable, func_name: []const u8) ?*const ExternalSymbol {
        return self.symbols.getPtr(func_name);
    }
    
    /// Iterator over all symbols
    pub fn iterator(self: *const ExternalSymbolTable) std.StringHashMap(ExternalSymbol).Iterator {
        return self.symbols.iterator();
    }
    
    /// Get count of external symbols
    pub fn count(self: *const ExternalSymbolTable) usize {
        return self.symbols.count();
    }
};

/// Reference to an external symbol (a call site)
pub const SymbolReference = struct {
    /// Offset in code where this reference occurs
    code_offset: u32,
};

/// External Symbol - represents an imported function
pub const ExternalSymbol = struct {
    /// Function name (e.g., "puts", "malloc")
    name: []const u8,
    
    /// Library hint for Windows (e.g., "msvcrt.dll"), null for Linux
    library_hint: ?[]const u8,
    
    /// List of references (call sites) to this function
    /// These will be patched to call the stub or emit relocations
    references: std.ArrayList(SymbolReference),
    
    /// Offset of the PLT stub (Linux) or jump stub (Windows)
    /// Filled during stub generation phase
    stub_offset: ?u32,
    
    /// Index in GOT (Linux) or IAT (Windows)
    /// Filled during GOT/IAT construction phase
    got_iat_index: ?u32,
    
    pub fn deinit(self: *ExternalSymbol, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.library_hint) |lib| {
            allocator.free(lib);
        }
        self.references.deinit(allocator);
    }
};

/// Platform-specific stub generator trait
/// Implemented by ELF, PE, etc. writers
pub const StubGenerator = struct {
    /// Generate a stub for an external symbol
    /// Returns the offset of the generated stub
    generateStubFn: *const fn (ctx: *anyopaque, symbol: *const ExternalSymbol) anyerror!u32,
    
    /// Patch call sites to point to stubs
    patchCallSitesFn: *const fn (ctx: *anyopaque, table: *const ExternalSymbolTable) anyerror!void,
    
    /// Context pointer (the writer instance)
    ctx: *anyopaque,
    
    pub fn generateStub(self: *const StubGenerator, symbol: *const ExternalSymbol) !u32 {
        return self.generateStubFn(self.ctx, symbol);
    }
    
    pub fn patchCallSites(self: *const StubGenerator, table: *const ExternalSymbolTable) !void {
        return self.patchCallSitesFn(self.ctx, table);
    }
};
