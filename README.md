# HolyCross

A modern cross-platform HolyC compiler written in Zig that enables developers to write TempleOS software from Linux, Windows, and macOS.

## Project Status

🚧 **Under Active Development** 🚧

Currently in Phase 0: Foundation. The compiler infrastructure is being built. See [PLAN.md](PLAN.md) for the complete development roadmap.

### Current Capabilities
- ✅ Project structure and build system
- ✅ Basic CLI interface
- ⏳ Lexer (in progress)
- ⏳ Parser (planned)
- ⏳ Code generation (planned)
- ⏳ Binary output (planned)

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

```bash
# Compile a HolyC file
holycc input.hc

# Specify output file
holycc input.hc -o output

# Show help
holycc --help
```

## Project Structure

```
HolyCross/
├── src/                    # Source code
│   ├── main.zig           # Entry point
│   ├── lexer/             # Lexical analysis
│   ├── parser/            # Parsing
│   ├── semantic/          # Semantic analysis
│   ├── ir/                # Intermediate representation
│   ├── codegen/           # Code generation
│   ├── binary/            # Binary format writers
│   └── runtime/           # Runtime support
├── tests/                  # Test suites
├── examples/               # Example HolyC programs
├── docs/                   # Documentation
├── PLAN.md                # Detailed project plan
├── LICENSE                # LGPL v3
└── README.md              # This file
```

## Development Phases

The project follows an incremental development approach:

- **Phase 0**: Foundation (✅ Complete)
- **Phase 1**: Expression Evaluator (⏳ In Progress)
- **Phase 2**: Hello World (Native Linux)
- **Phase 3-7**: Core language features
- **Phase 8**: TempleOS binary format
- **Phase 9+**: Advanced features

See [PLAN.md](PLAN.md) for detailed milestones and timelines.

## Contributing

This is currently a personal learning project. Contributions, suggestions, and bug reports are welcome once the core compiler reaches Phase 2.

## License

This project is licensed under the GNU Lesser General Public License v3.0 (LGPL-3.0). See [LICENSE](LICENSE) for details.

## Acknowledgments

- **Terry A. Davis**: Creator of TempleOS and HolyC
- **Zeal OS Team**: Continued development and documentation
- **Zig Community**: Excellent language and tooling

## Resources

- [TempleOS GitHub](https://github.com/cia-foundation/TempleOS)
- [ZealOS GitHub](https://github.com/Zeal-Operating-System/ZealOS)
- [Project Documentation](docs/)

---

*"God said 640x480 16 color was a covenant like the rainbow." - Terry A. Davis*
