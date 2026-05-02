# Zig 0.16.0 Migration Guide for HolyCross

This document tracks the changes needed to upgrade HolyCross from Zig 0.15.2 to 0.16.0.

## Key Changes from Release Notes

### 1. Standard Library Changes

#### ArrayList (Already Compatible)
- ArrayList is now "unmanaged" style in both 0.15.2 and 0.16.0
- Our code already uses: `ArrayList{}` init and `.deinit(allocator)`
- ✅ **No changes needed**

#### mem Module Changes
- `indexOf` renamed to `find`
- `indexOfScalar` renamed to `findScalar`  
- `lastIndexOf` renamed to `findLast`
- `lastIndexOfScalar` renamed to `findLastScalar`
- New `cut` functions added
- 🔧 **Need to update** our code if we use any of these

#### I/O Changes
- Major rework: "I/O as an Interface"
- `GenericReader`, `AnyReader`, `FixedBufferStream` removed
- `{D}` format specifier replaced with `Io.Duration.format()`
- 🔧 **Need to review** our I/O usage

### 2. Build System Changes

#### Module Creation
- Need to verify `b.createModule()` API is still the same
- `b.path()` should still work
- 🔍 **Need to test** build system

### 3. Language Changes (Unlikely to Affect Us)

Most language changes are about `switch`, `packed union`, `@Type` removal, etc.
These shouldn't affect our current codebase significantly.

## Files That May Need Updates

### High Priority

1. **src/lexer/lexer.zig** - May use `indexOf` 
2. **src/parser/parser.zig** - May use `indexOf`
3. **src/semantic/*.zig** - May use `indexOf`
4. **src/codegen/*.zig** - May use `indexOf`
5. **build.zig** - Verify Build System API

### Medium Priority

6. **src/main.zig** - Check I/O usage
7. **tools/assembler_demo.zig** - Check I/O usage

## Migration Steps

### Step 1: Update Version Requirements
- [ ] Update README.md to require Zig 0.16.0+
- [ ] Update docs/GETTING_STARTED.md
- [ ] Update docs/PLAN.md

### Step 2: Search and Replace
- [ ] Search for `indexOf` and replace with `find`
- [ ] Search for `indexOfScalar` and replace with `findScalar`
- [ ] Search for `lastIndexOf` and replace with `findLast`
- [ ] Search for `lastIndexOfScalar` and replace with `findLastScalar`

### Step 3: Test Everything
- [ ] Run `zig build test`
- [ ] Run `zig build test-asm`
- [ ] Run `zig build demo-asm`
- [ ] Fix any compilation errors

### Step 4: Review I/O Code
- [ ] Check if we use any removed I/O APIs
- [ ] Update if necessary

## Breaking Changes We Need to Handle

Based on the release notes, the main things we need to handle are:

1. **mem.indexOf → mem.find** (and related functions)
2. **I/O API changes** (if we use advanced I/O)
3. **Build system verification**

## Notes

- ArrayList changes are already compatible ✅
- Most language changes don't affect us ✅
- Main work is renaming `indexOf` functions 📝
