const std = @import("std");
const builtin = @import("builtin");

/// Global allocator strategy using conditional compilation
/// - Debug builds: DebugAllocator (detects leaks, double-free, use-after-free)
/// - Release builds: ArenaAllocator with paged allocator (fast, bulk cleanup)
pub const GlobalAllocator = if (builtin.mode == .Debug)
    std.heap.DebugAllocator(.{})
else
    std.heap.ArenaAllocator;

/// Initialize the global allocator
pub fn init() GlobalAllocator {
    if (builtin.mode == .Debug) {
        return std.heap.DebugAllocator(.{}){};
    } else {
        return std.heap.ArenaAllocator.init(std.heap.page_allocator);
    }
}

/// Get the allocator interface
pub fn allocator(gpa: *GlobalAllocator) std.mem.Allocator {
    if (builtin.mode == .Debug) {
        return gpa.allocator();
    } else {
        return gpa.allocator();
    }
}

/// Deinitialize the allocator and check for leaks in debug mode
pub fn deinit(gpa: *GlobalAllocator) void {
    if (builtin.mode == .Debug) {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected!", .{});
        }
    } else {
        gpa.deinit();
    }
}
