# Zig 0.16 API Notes

This document tracks Zig 0.16-specific API behaviors and quirks encountered during development.

## ArrayList API

### Initialization with `fromOwnedSlice`

**Correct pattern:**
```zig
const empty_items = try allocator.alloc(T, 0);
const list = std.ArrayList(T).fromOwnedSlice(empty_items);
```

**Key behaviors:**
- `fromOwnedSlice()` takes only the slice, NOT an allocator
- The ArrayList does NOT store an allocator internally
- `append()` requires passing an allocator: `list.append(allocator, item)`
- `deinit()` requires passing an allocator: `list.deinit(allocator)`

### Empty ArrayList Deallocation Bug

**Issue:**
When an ArrayList is created with `fromOwnedSlice(empty_slice)` and remains empty (no items appended), calling `deinit(allocator)` can cause a segfault.

**Workaround:**
```zig
if (self.list.items.len > 0) {
    self.list.deinit(allocator);
} else {
    // Empty list allocated with fromOwnedSlice needs special handling
    allocator.free(self.list.allocatedSlice());
}
```

**Root cause:**
The ArrayList's internal state when created from an empty slice doesn't properly handle deallocation. When items are appended, the list reallocates and the issue doesn't occur.

**Files affected:**
- `src/codegen/x64_machine_code.zig` (forward_jumps ArrayList)

## Time API

**Changed:**
```zig
// Zig 0.13 and earlier
const timestamp = std.time.timestamp();

// Zig 0.16
const timestamp = @as(u32, @intCast(std.time.timestamp()));
```

**Reason:**
`std.time.timestamp()` now returns `i64` instead of `u32`. Explicit casting required.

**Files affected:**
- `src/codegen/pe_writer.zig`
- `src/codegen/coff_object.zig`

## Case Sensitivity

**Issue:**
`std.Io` is case-sensitive in Zig 0.16.

**Correct:**
```zig
const std = @import("std");
// Use std.io NOT std.Io
const writer = std.io.getStdOut().writer();
```

**Files affected:**
- Various writer modules

## ArrayList vs. fromOwnedSlice Usage Patterns

### Pattern 1: Simple dynamic growth (preferred for most cases)
```zig
// Would use init() in newer Zig, but 0.16 doesn't have it
// Use fromOwnedSlice with empty allocation instead:
const empty = try allocator.alloc(T, 0);
var list = std.ArrayList(T).fromOwnedSlice(empty);
defer list.deinit(allocator);

try list.append(allocator, item);
```

### Pattern 2: Pre-allocated slice handoff
```zig
const items = try allocator.alloc(T, initial_size);
// ... fill items ...
var list = std.ArrayList(T).fromOwnedSlice(items);
defer list.deinit(allocator);
```

**Note:** Most codebases use Pattern 2 even for empty lists for consistency.

## StringHashMap API

**Correct usage:**
```zig
var map = std.StringHashMap(T).init(allocator);
defer {
    var iter = map.keyIterator();
    while (iter.next()) |key| {
        allocator.free(key.*);
    }
    map.deinit();
}
```

**Key points:**
- Keys are NOT automatically freed by `deinit()`
- Must manually iterate and free string keys
- Values are freed automatically if they're directly stored (not pointers)

## Memory Management Best Practices

### Allocator Strategy (from `src/allocator.zig`)
```zig
// Debug builds
var debug_allocator = std.heap.DebugAllocator.init();
const allocator = debug_allocator.allocator();

// Release builds  
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();
```

### Owned String Duplication
```zig
const owned_name = try allocator.dupe(u8, source_name);
// Later:
allocator.free(owned_name);
```

## Common Gotchas

1. **ArrayList allocated with `fromOwnedSlice` on empty slice**: Use the special deinit pattern or ensure items are added
2. **Forgetting to pass allocator to `append()`**: Compiler error, but easy to miss
3. **Not freeing StringHashMap keys**: Memory leak
4. **Using `std.Io` instead of `std.io`**: Case sensitivity matters
5. **Assuming `timestamp()` returns `u32`**: It's now `i64`, requires cast

## Testing Memory Leaks

Use DebugAllocator to catch leaks:
```zig
test "memory leak detection" {
    var debug_allocator = std.heap.DebugAllocator.init();
    defer debug_allocator.deinit(); // Will report leaks
    
    const allocator = debug_allocator.allocator();
    // ... your code ...
}
```

## References

- Zig 0.16 Standard Library: `/usr/lib/zig/std/`
- ArrayList implementation: `/usr/lib/zig/std/array_list.zig`
- See `src/allocator.zig` for project-specific allocator patterns
