//! Type Layout System
//!
//! This module manages memory layout information for composite types (classes and unions).
//! It calculates member offsets and total size for proper code generation.

const std = @import("std");
const ast = @import("../parser/ast.zig");
const Allocator = std.mem.Allocator;

/// Information about a single member's layout
pub const MemberLayout = struct {
    name: []const u8,
    type: ast.Type,
    offset: u64, // Byte offset from start of struct
    size: u64, // Size of this member in bytes
};

/// Complete layout information for a composite type
pub const TypeLayout = struct {
    name: []const u8,
    kind: enum { class_type, union_type },
    total_size: u64, // Total size in bytes
    alignment: u64, // Alignment requirement (typically 8 for x64)
    members: []MemberLayout,

    /// Calculate layout for a class (struct)
    /// Members are laid out sequentially with padding for alignment
    pub fn fromClass(allocator: Allocator, name: []const u8, members: []const ast.ClassMember) !TypeLayout {
        const empty_layouts = try allocator.alloc(MemberLayout, 0);
        var member_layouts = std.ArrayList(MemberLayout).fromOwnedSlice(empty_layouts);
        defer member_layouts.deinit(allocator);

        var current_offset: u64 = 0;
        var max_alignment: u64 = 1;

        for (members) |member| {
            const member_size = calculateMemberSize(member.type);
            const member_alignment = calculateAlignment(member.type);

            // Update maximum alignment
            if (member_alignment > max_alignment) {
                max_alignment = member_alignment;
            }

            // Align current offset to member's alignment requirement
            current_offset = alignOffset(current_offset, member_alignment);

            try member_layouts.append(allocator, .{
                .name = member.name,
                .type = member.type,
                .offset = current_offset,
                .size = member_size,
            });

            current_offset += member_size;
        }

        // Align total size to struct's alignment
        const total_size = alignOffset(current_offset, max_alignment);

        return .{
            .name = name,
            .kind = .class_type,
            .total_size = total_size,
            .alignment = max_alignment,
            .members = try allocator.dupe(MemberLayout, member_layouts.items),
        };
    }

    /// Calculate layout for a union
    /// All members start at offset 0, total size is the largest member
    pub fn fromUnion(allocator: Allocator, name: []const u8, members: []const ast.ClassMember) !TypeLayout {
        const empty_layouts = try allocator.alloc(MemberLayout, 0);
        var member_layouts = std.ArrayList(MemberLayout).fromOwnedSlice(empty_layouts);
        defer member_layouts.deinit(allocator);

        var max_size: u64 = 0;
        var max_alignment: u64 = 1;

        for (members) |member| {
            const member_size = calculateMemberSize(member.type);
            const member_alignment = calculateAlignment(member.type);

            if (member_size > max_size) {
                max_size = member_size;
            }
            if (member_alignment > max_alignment) {
                max_alignment = member_alignment;
            }

            // All union members start at offset 0
            try member_layouts.append(allocator, .{
                .name = member.name,
                .type = member.type,
                .offset = 0,
                .size = member_size,
            });
        }

        // Align total size to union's alignment
        const total_size = alignOffset(max_size, max_alignment);

        return .{
            .name = name,
            .kind = .union_type,
            .total_size = total_size,
            .alignment = max_alignment,
            .members = try allocator.dupe(MemberLayout, member_layouts.items),
        };
    }

    /// Find a member by name and return its offset
    pub fn getMemberOffset(self: *const TypeLayout, member_name: []const u8) ?u64 {
        for (self.members) |member| {
            if (std.mem.eql(u8, member.name, member_name)) {
                return member.offset;
            }
        }
        return null;
    }

    /// Get member layout by name
    pub fn getMember(self: *const TypeLayout, member_name: []const u8) ?MemberLayout {
        for (self.members) |member| {
            if (std.mem.eql(u8, member.name, member_name)) {
                return member;
            }
        }
        return null;
    }
};

/// Calculate size of a type in bytes
fn calculateMemberSize(typ: ast.Type) u64 {
    return switch (typ) {
        .i0, .u0 => 0,
        .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32 => 4,
        .i64, .u64, .f64, .bool => 8, // Bool is 8 bytes (I64)
        .pointer => 8, // Pointers are 8 bytes on x64
        .array => |arr| {
            const elem_size = calculateMemberSize(arr.element_type.*);
            if (arr.size) |size| {
                return elem_size * size;
            }
            return 8; // Unsized array as pointer
        },
        .named => 8, // Named types - default size, should be looked up
        .function => 8, // Function pointers
    };
}

/// Calculate alignment requirement for a type
fn calculateAlignment(typ: ast.Type) u64 {
    return switch (typ) {
        .i0, .u0 => 1,
        .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32 => 4,
        .i64, .u64, .f64, .bool => 8, // Bool aligned as I64
        .pointer => 8,
        .array => |arr| calculateAlignment(arr.element_type.*),
        .named => 8, // Named types - should be looked up
        .function => 8,
    };
}

/// Align an offset to the specified alignment
fn alignOffset(offset: u64, alignment: u64) u64 {
    if (alignment == 0) return offset;
    const remainder = offset % alignment;
    if (remainder == 0) {
        return offset;
    }
    return offset + (alignment - remainder);
}

// Tests
const testing = std.testing;

test "TypeLayout: simple class" {
    const allocator = testing.allocator;

    const members = [_]ast.ClassMember{
        .{ .type = .i32, .name = "x", .loc = .{ .line = 1, .column = 1 } },
        .{ .type = .i32, .name = "y", .loc = .{ .line = 2, .column = 1 } },
    };

    const layout = try TypeLayout.fromClass(allocator, "Point", &members);
    defer allocator.free(layout.members);

    try testing.expectEqual(@as(u64, 8), layout.total_size); // 4 + 4
    try testing.expectEqual(@as(u64, 0), layout.members[0].offset);
    try testing.expectEqual(@as(u64, 4), layout.members[1].offset);
}

test "TypeLayout: class with different sizes" {
    const allocator = testing.allocator;

    const members = [_]ast.ClassMember{
        .{ .type = .i8, .name = "a", .loc = .{ .line = 1, .column = 1 } },
        .{ .type = .i64, .name = "b", .loc = .{ .line = 2, .column = 1 } },
        .{ .type = .i8, .name = "c", .loc = .{ .line = 3, .column = 1 } },
    };

    const layout = try TypeLayout.fromClass(allocator, "Mixed", &members);
    defer allocator.free(layout.members);

    // a: offset 0, size 1
    // padding to align b to 8: offset 8
    // b: offset 8, size 8
    // c: offset 16, size 1
    // padding to align total to 8: 24
    try testing.expectEqual(@as(u64, 0), layout.members[0].offset);
    try testing.expectEqual(@as(u64, 8), layout.members[1].offset);
    try testing.expectEqual(@as(u64, 16), layout.members[2].offset);
    try testing.expectEqual(@as(u64, 24), layout.total_size);
}

test "TypeLayout: union" {
    const allocator = testing.allocator;

    const members = [_]ast.ClassMember{
        .{ .type = .i32, .name = "as_int", .loc = .{ .line = 1, .column = 1 } },
        .{ .type = .f64, .name = "as_float", .loc = .{ .line = 2, .column = 1 } },
    };

    const layout = try TypeLayout.fromUnion(allocator, "Value", &members);
    defer allocator.free(layout.members);

    // Union: all members at offset 0, size = largest member
    try testing.expectEqual(@as(u64, 8), layout.total_size); // max(4, 8) = 8
    try testing.expectEqual(@as(u64, 0), layout.members[0].offset);
    try testing.expectEqual(@as(u64, 0), layout.members[1].offset);
}

test "TypeLayout: getMemberOffset" {
    const allocator = testing.allocator;

    const members = [_]ast.ClassMember{
        .{ .type = .i64, .name = "first", .loc = .{ .line = 1, .column = 1 } },
        .{ .type = .i64, .name = "second", .loc = .{ .line = 2, .column = 1 } },
    };

    const layout = try TypeLayout.fromClass(allocator, "Pair", &members);
    defer allocator.free(layout.members);

    try testing.expectEqual(@as(?u64, 0), layout.getMemberOffset("first"));
    try testing.expectEqual(@as(?u64, 8), layout.getMemberOffset("second"));
    try testing.expectEqual(@as(?u64, null), layout.getMemberOffset("nonexistent"));
}
