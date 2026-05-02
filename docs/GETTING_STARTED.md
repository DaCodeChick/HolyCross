# Getting Started with HolyCross

Welcome to HolyCross development! This guide will help you start contributing.

## Current Status

**Phase 0: Foundation** ✅ Complete
- Project structure established
- Build system configured
- Basic CLI working
- Token types defined

**Phase 1: Lexer** 🚧 Next Up
- Implement full tokenization
- Handle all HolyC keywords
- Parse operators and literals
- Comment handling

## Development Setup

### Prerequisites
```bash
# Zig 0.16.0 or later
zig version  # Should show 0.16.0+

# Git
git --version
```

### Building
```bash
# Build the compiler
zig build

# Run tests
zig build test

# Format code
zig build fmt

# Run the compiler
./zig-out/bin/holycc examples/hello.hc
```

## Project Structure

```
HolyCross/
├── src/
│   ├── main.zig              # CLI entry point
│   ├── lexer/
│   │   └── lexer.zig         # Tokenization (IN PROGRESS)
│   ├── parser/               # TODO: Phase 1
│   ├── codegen/              # TODO: Phase 2+
│   └── ...
├── tests/
│   ├── unit/                 # Unit tests
│   ├── integration/          # End-to-end tests
│   └── vm_validation/        # TempleOS VM tests
├── examples/
│   └── hello.hc              # Test programs
└── docs/
    ├── PLAN.md               # Complete roadmap
    └── GETTING_STARTED.md    # This file
```

## Next Steps: Phase 1 - Lexer

### What We Need to Implement

1. **Keyword Recognition**
   - Type keywords: `U0`, `U8`, `I64`, `F64`, etc.
   - Control flow: `if`, `else`, `while`, `for`, `switch`, etc.
   - Class-related: `class`, `union`, `sizeof`, `offset`
   - Special: `asm`, `try`, `catch`, `throw`

2. **Operator Tokenization**
   - Arithmetic: `+`, `-`, `*`, `/`, `%`
   - Bitwise: `&`, `|`, `^`, `~`, `<<`, `>>`
   - Logical: `&&`, `||`, `!`
   - Comparison: `<`, `>`, `==`, `!=`, `<=`, `>=`
   - Special: `` ` `` (power operator in HolyC)

3. **Literal Parsing**
   - Integer: `42`, `0xFF`, `0b1010`
   - Float: `3.14`, `1.0e10`
   - String: `"Hello, World!\n"`
   - Character: `'A'`, `'\n'`
   - Multi-char: `'Hello'` (HolyC-specific!)

4. **Comment Handling**
   - Line comments: `// comment`
   - Block comments: `/* comment */`

### Development Workflow

1. **Write a test** for the feature
   ```zig
   test "tokenize keywords" {
       const source = "I64 x = 42;";
       var lexer = Lexer.init(allocator, source);
       
       const tok1 = try lexer.nextToken();
       try testing.expect(tok1.type == .keyword_i64);
   }
   ```

2. **Implement the feature** in `src/lexer/lexer.zig`

3. **Run tests** to verify
   ```bash
   zig build test
   ```

4. **Test with real HolyC**
   ```bash
   ./zig-out/bin/holycc examples/hello.hc
   ```

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "Implement keyword tokenization"
   ```

## Learning Resources

### Lexer Development
- [Crafting Interpreters - Scanning](https://craftinginterpreters.com/scanning.html)
- [Compiler Design - Lexical Analysis](https://www.geeksforgeeks.org/introduction-of-lexical-analysis/)

### HolyC Language
- TempleOS GitHub: https://github.com/cia-foundation/TempleOS
- See `PLAN.md` for detailed HolyC feature analysis

### Zig Language
- Official docs: https://ziglang.org/documentation/master/
- Zig Learn: https://ziglearn.org/

## Tips for Success

1. **Start small**: Get one token type working perfectly before moving on
2. **Test extensively**: Edge cases are where bugs hide
3. **Read PLAN.md**: Detailed implementation guidance for each phase
4. **Ask questions**: Understanding "why" is as important as "how"
5. **Celebrate wins**: Each working feature is progress!

## Communication

When working on code:
- Commit messages should be clear and descriptive
- Document complex logic with comments
- Update this doc as you learn

## Ready to Code?

Let's start with Phase 1! The first task is implementing keyword recognition in the lexer.

Want to jump in? Just say the word and we'll begin! 🚀
