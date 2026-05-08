# HolyCross

A modern cross-platform HolyC compiler written in Zig that enables developers to write TempleOS software from Linux, Windows, and macOS.

## Project Status

🚀 **Functional Compiler** 🚀

The HolyCross compiler can now compile HolyC programs to working x64 Linux executables!

### Current Capabilities
- ✅ Full lexer with all HolyC token types
- ✅ Complete recursive descent parser with Pratt expression parsing
- ✅ Preprocessor with #define, #ifdef, #include support
- ✅ Semantic analysis with type checking and symbol resolution
- ✅ IR generation and x64 code generation
- ✅ Inline assembly support (asm { } blocks)
- ✅ Multi-variable declarations (I64 a, b, c;)
- ✅ Classes, unions, arrays, pointers
- ✅ Control flow (if, while, for, do-while, switch)
- ✅ Function calls and returns
- ✅ Binary operators, unary operators, assignments
- ⏳ Full TempleOS compatibility (in progress)

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed compiler architecture and design.

## About

HolyC is the programming language created by Terry A. Davis for TempleOS. This project aims to bring HolyC to modern development environments while maintaining compatibility with TempleOS binaries.

### Goals
1. Compile HolyC source code to working binaries
2. Support native Linux x64 execution for rapid development
3. Generate TempleOS-compatible .BIN executables
4. Handle core HolyC language features (classes, inline assembly, #exe directive)
5. Enable compilation of significant TempleOS applications

## Building

### Prerequisites
- Zig 0.16.0 or later
- Linux x64 (primary development platform)
- Windows or macOS (future support)

### Build Instructions

```bash
# Clone the repository
git clone <your-repo-url>
cd HolyCross

# Build the compiler
zig build

# Run the compiler
./zig-out/bin/holycc examples/hello.hc

# Run tests
zig build test

# Format code
zig build fmt
```

## Usage

### Quick Start

Create a simple HolyC program:

```c
// hello.hc
I64 main()
{
    return 42;
}
```

Compile and run:

```bash
# Compile
./zig-out/bin/holycc hello.hc

# Run
./a.out
echo $?  # Should print: 42
```

### More Examples

```c
// Multi-variable declarations
I64 x = 10, y = 20, z = 30;

// Inline assembly
I64 GetValue()
{
    asm {
        MOV RAX, 42
    }
    return 0;
}

// Classes
class Point
{
    I64 x, y;
};

// Functions
I64 Add(I64 a, I64 b)
{
    return a + b;
}
```

### Command Line Options

```bash
# Compile a HolyC file
holycc input.hc

# Specify output file  
holycc input.hc -o output

# Show version
holycc --version

# Show help
holycc --help
```

## Project Structure

```
HolyCross/
├── src/                    # Source code
│   ├── main.zig           # Entry point
│   ├── preprocessor/      # Preprocessor (#define, #ifdef, etc.)
│   ├── lexer/             # Lexical analysis
│   ├── parser/            # Syntax analysis (AST generation)
│   ├── semantic/          # Semantic analysis & type checking
│   ├── codegen/           # IR generation & x64 code generation
│   ├── assembler/         # Inline assembly support
│   └── runtime/           # Runtime support (planned)
├── tests/                  # Test suites
├── examples/               # Example HolyC programs
├── ARCHITECTURE.md         # Compiler architecture documentation
├── PLAN.md                # Development roadmap
├── LICENSE                # LGPL v3
└── README.md              # This file
```

## Development Status

The project has moved beyond the initial phases:

- **Phase 0-2**: Foundation & Hello World (✅ Complete)
- **Phase 3-5**: Core Language Features (✅ Complete)
- **Phase 6-7**: Advanced Features (🚧 In Progress)
- **Phase 8**: TempleOS Binary Format (⏳ Planned)
- **Phase 9+**: Optimization & Polish (⏳ Planned)

### Recent Accomplishments
- Inline assembly support with `asm { }` blocks
- Multi-variable declarations (local and global)
- Full preprocessor with conditional compilation
- Complete x64 code generation pipeline
- Comprehensive test suite

See [PLAN.md](PLAN.md) for detailed roadmap and [ARCHITECTURE.md](ARCHITECTURE.md) for technical details.

## Contributing

This is currently a personal learning project. Contributions, suggestions, and bug reports are welcome once the core compiler reaches Phase 2.

## License

This project is licensed under the GNU Lesser General Public License v3.0 (LGPL-3.0). See [LICENSE](LICENSE) for details.

## Acknowledgments

- **Terry A. Davis**: Creator of TempleOS and HolyC
- **Zeal OS Team**: Continued development and documentation
- **Zig Community**: Excellent language and tooling

## Resources

- [Compiler Architecture](ARCHITECTURE.md) - Detailed technical documentation
- [Development Plan](PLAN.md) - Roadmap and milestones
- [TempleOS Archive](https://github.com/cia-foundation/TempleOS) - Original TempleOS source
- [ZealOS](https://github.com/Zeal-Operating-System/ZealOS) - Modern TempleOS continuation
- [HolyC Language Reference](src/assembler/README.md) - Inline assembly documentation

---

*"God said 640x480 16 color was a covenant like the rainbow." - Terry A. Davis*
