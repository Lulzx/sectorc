# Sectorc: Trustworthy Bootstrap Compiler Chain

A verifiable C compiler bootstrapped from a minimal, human-auditable seed. This project solves the "trusting trust" problem by ensuring every stage of the bootstrap chain is small enough for manual verification.

## Overview

```
Stage 0       Stage 1       Stage 2       Stage 3       Stage 4       Stage 5
┌────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
│ Hex    │──▶│ Minimal │──▶│Extended │──▶│ Subset  │──▶│  C89    │──▶│  C99    │
│ Loader │   │ Forth   │   │ Forth   │   │   C     │   │Compiler │   │Compiler │
│  (C)   │   │ (asm)   │   │ (Forth) │   │ (Forth) │   │  (C)    │   │  (C)    │
└────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘
```

**Current Status:** Stages 0-3 are functional. The bootstrap pipeline successfully:
1. Loads the Forth interpreter from hex format
2. Extends it with control flow and utility words
3. Runs a C compiler written in Forth
4. Outputs valid ARM64 assembly

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
├── stage0/           # Hex loader
│   ├── stage0.c      # C implementation with macOS JIT support
│   └── stage0.s      # ARM64 assembly reference
├── stage1/           # Minimal Forth interpreter
│   └── forth.s       # ARM64 assembly (converted to hex for loading)
├── stage2/           # Extended Forth
│   └── forth.fth     # Forth source: control flow, stack ops
├── stage3/           # Subset C compiler
│   └── cc.fth        # Forth source: compiles C to ARM64 assembly
├── stage4/           # C89 compiler
│   └── cc.c          # Full C89 with struct/union/enum
├── stage5/           # C99 compiler
│   └── cc.c          # C99 extensions
├── tools/            # Build utilities
│   └── macho_to_hex.sh  # Convert Mach-O binary to hex
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

Written in Forth, loaded by Stage 1. Adds higher-level words needed for compiler construction.

**Features:**
- Control flow: IF/THEN/ELSE, BEGIN/UNTIL/AGAIN
- Stack operations: NIP, TUCK, ?DUP, ROT, 2DROP, 2DUP
- Compilation helpers: [COMPILE]
- I/O utilities: SPACE, CR
- Comments: \ (backslash comments)

### Stage 3: Subset C Compiler

`stage3/cc` compiles a C subset to ARM64 assembly.

**Features:**
- Types: int, pointers, arrays
- Statements: if/else, while, for, return
- Expressions: arithmetic, comparison, assignment
- Function definitions and calls (incl. recursion)

**Bootstrappable Stage 3 (`stage3/cc.fth`):**
- Runs on Stage 1 + Stage 2 and compiles `tests/stage3/*.c` to ARM64 assembly (used by `bootstrap.sh`).
- The host `stage3/cc` binary is currently a convenience wrapper around the Stage 4 implementation.

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
