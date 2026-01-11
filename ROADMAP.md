# HolyCross Compiler Roadmap

This document outlines the development roadmap for the HolyCross compiler.

## Completed Features

### Priority 1 - Core Language Features
- ✅ Top-level statement execution (commit `e1effd4`)
- ✅ Extern forward declarations (commit `b195ea4`)
- ✅ Array syntax `Type name[size]` (commit `5e439a0`)

### Priority 2 - Essential Features
- ✅ Top-level #define preprocessor directives (simple constant substitution)

## Current Focus

### Priority 3 - Object-Oriented Features
- 🔄 **Class inheritance syntax** - IN PROGRESS
- ⏳ Enhanced array codegen - Better array handling in code generation

## Future Work

### Preprocessor Enhancements
- `#if` / `#else` / `#endif` conditional compilation
- `#ifdef` / `#ifndef` macro existence checks
- `#undef` to undefine macros
- Multi-line macro definitions (if needed)

### Control Flow Improvements
- Enhanced switch statement codegen
- Better optimization for conditional branches

### Type System
- Additional type qualifiers and modifiers
- Better type inference where applicable

### Code Generation
- Optimization passes
- Better register allocation
- Dead code elimination

### Standard Library
- Core TempleOS API compatibility layer
- Common utility functions
- String manipulation functions

### Tooling
- Better error messages with suggestions
- Debug information generation
- Profiling support

## Fringe Goals (Low Priority)

These features are documented but not currently prioritized for implementation:

- Type qualifier `i` suffix (e.g., `U16i union U16 { ... }`) - needs research to understand exact semantics
- Advanced preprocessor features (stringification, token pasting)
- Inline assembly with better integration
- Additional optimization levels

## Contributing

If you're interested in contributing to HolyCross, check the "Current Focus" section for what we're actively working on. Feel free to pick up items from "Future Work" or propose new features!

## Notes

- HolyCross aims for practical HolyC compatibility, not 100% feature parity with TempleOS
- Focus is on supporting real TempleOS code compilation
- Performance and correctness take priority over exotic features
