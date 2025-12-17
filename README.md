# Sectorc: Trustworthy Bootstrap Compiler Chain

A verifiable C compiler bootstrapped from a minimal, human-auditable seed. This project solves the "trusting trust" problem by ensuring every stage of the bootstrap chain is small enough for manual verification.

## Overview

```
Stage 0       Stage 1       Stage 2       Stage 3       Stage 4       Stage 5
┌────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
│ Hex    │──▶│ Minimal │──▶│Extended │──▶│ Subset  │──▶│  C89    │──▶│  C99    │
│ Loader │   │ Forth   │   │ Forth   │   │   C     │   │Compiler │   │Compiler │
│ ~512B  │   │ ~2KB    │   │ ~8KB    │   │ ~15KB   │   │ ~40KB   │   │ ~80KB   │
└────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘
```

## Building

### Prerequisites

- macOS with Apple Silicon (ARM64)
- Xcode Command Line Tools (`xcode-select --install`)
- clang compiler

### Quick Start

```bash
# Build all stages
make

# Run all tests
make test

# Full bootstrap with verification
./bootstrap.sh
```

### Building Individual Stages

```bash
# Stage 0: Hex Loader
make stage0

# Stage 1: Minimal Forth
make stage1

# Stage 2: Extended Forth
make stage2

# Stage 3: Subset C Compiler
make stage3

# Stage 4: C89 Compiler
make stage4

# Stage 5: C99 Compiler
make stage5
```

## Project Structure

```
sectorc/
├── stage0/           # Hex loader (~512 bytes)
│   ├── stage0.c      # C implementation with macOS JIT support
│   └── stage0.s      # ARM64 assembly reference
├── stage1/           # Minimal Forth interpreter
│   ├── forth.c       # C implementation
│   └── forth.s       # ARM64 assembly reference
├── stage2/           # Extended Forth
│   └── forth.c       # Adds strings, file I/O, control flow
├── stage3/           # Subset C compiler
│   └── cc.c          # Compiles to ARM64 assembly
├── stage4/           # C89 compiler
│   └── cc.c          # Full C89 with struct/union/enum
├── stage5/           # C99 compiler
│   └── cc.c          # C99 extensions
├── tests/            # Test suites for each stage
├── bootstrap.sh      # Full bootstrap script
└── Makefile          # Top-level build
```

## Stage Details

### Stage 0: Hex Loader

Reads ASCII hexadecimal from stdin, converts to binary, executes it.

**Features:**
- Whitespace handling (spaces, tabs, newlines)
- Comment support (# and ;)
- Case-insensitive hex digits
- JIT execution on ARM64 macOS

### Stage 1: Minimal Forth

A direct-threaded Forth interpreter with ~65 primitive words.

**Features:**
- Stack operations (DUP, DROP, SWAP, OVER, ROT)
- Arithmetic (+, -, *, /, MOD)
- Comparison (<, >, =)
- Memory access (@, !, C@, C!)
- I/O (EMIT, KEY, .)

### Stage 2: Extended Forth

Adds advanced features for building a compiler.

**Features:**
- String handling (S", TYPE, COMPARE)
- File I/O (OPEN-FILE, READ-FILE, INCLUDE)
- Conditional compilation ([IF], [ELSE], [THEN])
- Comments (\ and ( ))

### Stage 3: Subset C Compiler

Compiles a useful subset of C to ARM64 assembly.

**Supported:**
- Types: int, char, void, pointers, arrays
- Statements: if/else, while, for, return
- Expressions: arithmetic, comparison, logical
- Function definitions and calls

### Stage 4: C89 Compiler

Full C89 implementation.

**Additional features:**
- struct, union, enum
- switch/case
- typedef
- Basic preprocessor (#define, #include)

### Stage 5: C99 Compiler

C99 extensions (in progress).

## Verification

Each stage produces verifiable artifacts:

```bash
# Generate verification hashes
make verify

# Full bootstrap creates manifest.txt
./bootstrap.sh
```

## Testing

```bash
# Run all tests
make test

# Run individual stage tests
cd tests/stage0 && ./run_tests.sh
cd tests/stage1 && ./run_tests.sh
cd tests/stage2 && ./run_tests.sh
cd tests/stage3 && ./run_tests.sh
cd tests/stage4 && ./run_tests.sh
```

## Security Considerations

This project addresses the "trusting trust" problem:

1. **Stage 0** is small enough (~512 bytes of logic) for complete manual audit
2. Each subsequent stage is compiled by the previous trusted stage
3. All source code is auditable
4. Verification hashes ensure reproducibility

**Trust assumptions:**
- Your CPU executes documented instructions correctly
- Your disassembler is accurate
- Auditors are competent

## License

MIT License

## References

- Ken Thompson, "Reflections on Trusting Trust" (1984)
- [Bootstrappable Builds](https://bootstrappable.org/)
- [stage0](https://github.com/oriansj/stage0)
