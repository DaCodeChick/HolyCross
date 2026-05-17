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

## Case Sensitivity and I/O APIs

### std.Io vs std.io
In Zig 0.16, `std.Io` (capital I) is the actual I/O subsystem used for file operations.

**File operations:**
```zig
const cwd = std.Io.Dir.cwd();
const file = try cwd.createFile(io, path, .{});
defer file.close(io);

var write_buffer: [8192]u8 = undefined;
var buffered_writer = file.writer(io, &write_buffer);
defer buffered_writer.flush() catch {};
var writer = buffered_writer.interface;
```

**Key points:**
- `std.Io.Dir.cwd()` to get current directory
- `createFile(io, path, .{})` requires io handle
- `file.close(io)` requires io handle
- `file.writer(io, &buffer)` creates buffered writer
- Writer must be `var` not `const` for writeStruct
- `buffered_writer.interface` is the actual writer
- `flush()` is automatic with defer

### Writer API Changes

**writeStruct now requires endianness:**
```zig
// Zig 0.13
try writer.writeStruct(header);

// Zig 0.16
try writer.writeStruct(header, .little);
```

**Writer must be mutable:**
```zig
// Wrong
const writer = buffered_writer.interface;

// Correct
var writer = buffered_writer.interface;
```

### File Position Tracking and Buffered Writing

`std.Io.File` does NOT have `getPos()` or `seekTo()` in Zig 0.16.

**Critical**: Don't extract buffered_writer.interface to a variable!
```zig
// WRONG - produces 0-byte files!
var writer = buffered_writer.interface;
try writer.writeAll(data);  // FAILS SILENTLY

// CORRECT - writes data successfully
try buffered_writer.interface.writeAll(data);
try buffered_writer.interface.writeStruct(header, .little);
```

**Position tracking - do it manually:**
```zig
var current_pos: u32 = 0;

try buffered_writer.interface.writeStruct(header, .little);
current_pos += @sizeOf(@TypeOf(header));

try buffered_writer.interface.writeAll(data);
current_pos += @intCast(data.len);

// Padding
while (current_pos < target_offset) {
    try buffered_writer.interface.writeByte(0);
    current_pos += 1;
}
```

**Files affected:**
- `src/codegen/macho_object.zig`

## ArrayList vs. fromOwnedSlice Usage Patterns

### ArrayList Struct Literal Initialization (Zig 0.16)

**Correct pattern:**
```zig
// NO .allocator field in struct literal!
var list = std.ArrayList(T){ .items = &.{}, .capacity = 0 };

// Methods still need allocator
try list.append(allocator, item);
list.deinit(allocator);
```

**Wrong pattern (causes error):**
```zig
// ERROR: no field named 'allocator'
var list = std.ArrayList(T){ .allocator = allocator, .items = &.{}, .capacity = 0 };
```

**Key points:**
- ArrayList struct does NOT have an `allocator` field in Zig 0.16
- Use only `.items` and `.capacity` in struct literal
- Pass allocator to methods that need it (append, deinit, etc.)
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
