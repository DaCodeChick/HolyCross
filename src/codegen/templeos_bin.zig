const std = @import("std");
const Allocator = std.mem.Allocator;

/// TempleOS binary file format structures and generation
/// Based on CBinFile from TempleOS Kernel/KernelA.HH

/// Import/Export Table entry types
pub const IET = enum(u8) {
    END = 0,
    REL_I0 = 1,
    IMM_U0 = 2,
    IMM_U8 = 3,
    REL_I8 = 4,
    IMM_U16 = 5,
    REL_I16 = 6,
    IMM_U32 = 7,
    REL_I32 = 8,
    ABS_ADDR = 9,
    CODE_HEAP = 10,
    DATA_HEAP = 11,
    ZEROED_DATA = 12,
    MAIN = 13, // Entry point
    // ... more types as needed

    pub fn fromU8(val: u8) !IET {
        return @enumFromInt(val);
    }
};

/// Import/Export Table entry
pub const IETEntry = struct {
    type: IET,
    /// Additional data depending on type
    /// For IET_ABS_ADDR, IET_REL_*, etc: offset in binary
    /// For IET_MAIN: entry point address
    data: u32,
};

/// TempleOS Binary File header
/// Corresponds to CBinFile structure
pub const BinFileHeader = struct {
    /// Signature: "TOSB" (TempleOS Binary)
    signature: [4]u8 = "TOSB".*,
    /// Org address (typically 0 for relocatable)
    org: u64 = 0,
    /// Patch table offset from start of file
    patch_table_offset: u32,
    /// Size of machine code
    code_size: u32,
    /// Number of patch table entries
    patch_table_size: u32,

    pub fn serialize(self: *const BinFileHeader, writer: anytype) !void {
        try writer.writeAll(&self.signature);
        try writer.writeInt(u64, self.org, .little);
        try writer.writeInt(u32, self.patch_table_offset, .little);
        try writer.writeInt(u32, self.code_size, .little);
        try writer.writeInt(u32, self.patch_table_size, .little);
    }
};

/// TempleOS Binary Writer
pub const TempleOSBinWriter = struct {
    allocator: Allocator,
    /// Machine code buffer
    code: std.ArrayList(u8),
    /// Patch table entries
    patch_table: std.ArrayList(IETEntry),
    /// Entry point offset (for IET_MAIN)
    entry_point: ?u32 = null,

    pub fn init(allocator: Allocator) !TempleOSBinWriter {
        const empty_code = try allocator.alloc(u8, 0);
        const empty_patches = try allocator.alloc(IETEntry, 0);
        return .{
            .allocator = allocator,
            .code = std.ArrayList(u8).fromOwnedSlice(empty_code),
            .patch_table = std.ArrayList(IETEntry).fromOwnedSlice(empty_patches),
        };
    }

    pub fn deinit(self: *TempleOSBinWriter) void {
        self.code.deinit(self.allocator);
        self.patch_table.deinit(self.allocator);
    }

    /// Append machine code bytes
    pub fn appendCode(self: *TempleOSBinWriter, bytes: []const u8) !void {
        try self.code.appendSlice(self.allocator, bytes);
    }

    /// Add a patch table entry
    pub fn addPatchEntry(self: *TempleOSBinWriter, entry: IETEntry) !void {
        try self.patch_table.append(self.allocator, entry);
    }

    /// Add an absolute address relocation at the given offset
    pub fn addAbsoluteRelocation(self: *TempleOSBinWriter, offset: u32) !void {
        try self.addPatchEntry(.{
            .type = .ABS_ADDR,
            .data = offset,
        });
    }

    /// Set the entry point (main function offset)
    pub fn setEntryPoint(self: *TempleOSBinWriter, offset: u32) !void {
        self.entry_point = offset;
        try self.addPatchEntry(.{
            .type = .MAIN,
            .data = offset,
        });
    }

    /// Write the complete .BIN file
    pub fn writeToBinFile(self: *TempleOSBinWriter, io: std.Io, path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        const file = try cwd.createFile(io, path, .{});
        defer file.close(io);

        // Build the complete binary in memory first
        var bin_data = std.ArrayList(u8).fromOwnedSlice(try self.allocator.alloc(u8, 0));
        defer bin_data.deinit(self.allocator);

        // Calculate patch table offset (after header + code)
        const header_size = 4 + 8 + 4 + 4 + 4; // signature + org + 3 u32s
        const patch_table_offset = header_size + self.code.items.len;

        // Build header
        const header = BinFileHeader{
            .org = 0,
            .patch_table_offset = @intCast(patch_table_offset),
            .code_size = @intCast(self.code.items.len),
            .patch_table_size = @intCast(self.patch_table.items.len),
        };

        // Write header to buffer
        try bin_data.appendSlice(self.allocator, &header.signature);
        const org_bytes = std.mem.toBytes(header.org);
        try bin_data.appendSlice(self.allocator, &org_bytes);
        const ptoff_bytes = std.mem.toBytes(header.patch_table_offset);
        try bin_data.appendSlice(self.allocator, &ptoff_bytes);
        const code_size_bytes = std.mem.toBytes(header.code_size);
        try bin_data.appendSlice(self.allocator, &code_size_bytes);
        const pt_size_bytes = std.mem.toBytes(header.patch_table_size);
        try bin_data.appendSlice(self.allocator, &pt_size_bytes);

        // Append machine code
        try bin_data.appendSlice(self.allocator, self.code.items);

        // Append patch table
        for (self.patch_table.items) |entry| {
            try bin_data.append(self.allocator, @intFromEnum(entry.type));
            const data_bytes = std.mem.toBytes(entry.data);
            try bin_data.appendSlice(self.allocator, &data_bytes);
        }

        // Append END marker
        try bin_data.append(self.allocator, @intFromEnum(IET.END));

        // Write all data to file using buffered IO
        var write_buffer: [8192]u8 = undefined;
        var buffered_writer = file.writer(io, &write_buffer);
        defer buffered_writer.flush() catch {};
        try buffered_writer.interface.writeAll(bin_data.items);
    }

    /// Get the current code offset (useful for tracking label positions)
    pub fn getCurrentOffset(self: *const TempleOSBinWriter) u32 {
        return @intCast(self.code.items.len);
    }
};

test "BinFileHeader serialize" {
    const testing = std.testing;
    const header = BinFileHeader{
        .org = 0x1000,
        .patch_table_offset = 0x200,
        .code_size = 0x100,
        .patch_table_size = 5,
    };

    var buf = std.ArrayList(u8).init(testing.allocator);
    defer buf.deinit();

    try header.serialize(buf.writer());

    try testing.expectEqual(@as(usize, 24), buf.items.len);
    try testing.expectEqualSlices(u8, "TOSB", buf.items[0..4]);
}

test "TempleOSBinWriter basic" {
    const testing = std.testing;

    var writer = try TempleOSBinWriter.init(testing.allocator);
    defer writer.deinit();

    // Add some code
    try writer.appendCode(&[_]u8{ 0x90, 0x90, 0x90 }); // NOPs
    try testing.expectEqual(@as(u32, 3), writer.getCurrentOffset());

    // Add relocation
    try writer.addAbsoluteRelocation(1);
    try testing.expectEqual(@as(usize, 1), writer.patch_table.items.len);
    try testing.expectEqual(IET.ABS_ADDR, writer.patch_table.items[0].type);
}
