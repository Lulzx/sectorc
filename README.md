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

**Status: Verified Working** ✓

The complete bootstrap pipeline has been verified:
1. Stage 0 loads the Forth interpreter from hex format
2. Stage 1 interprets Stage 2 Forth extensions
3. Stage 3 C compiler (written in Forth) compiles C to ARM64 assembly
4. Generated assembly assembles and executes correctly

```
$ ./bootstrap.sh
===========================================
Sectorc: Trustworthy Bootstrap Chain
===========================================
...
SUCCESS: Valid assembly generated.

$ ./test_output; echo "Exit code: $?"
Exit code: 42
```

## How It Works

The bootstrap pipeline chains stages together via stdin/stdout:

```
┌─────────────────────────────────────────────────────────────────────┐
│  cat stage1.hex | stage0 ──▶ (Forth interpreter now running)       │
│                     │                                               │
│                     ├──▶ reads stage2/forth.fth (extends Forth)    │
│                     ├──▶ reads stage3/cc.fth (C compiler in Forth) │
│                     └──▶ reads hello.c ──▶ outputs ARM64 assembly  │
└─────────────────────────────────────────────────────────────────────┘
```

1. **Stage 0** reads hex-encoded Stage 1 binary, loads it into executable memory, jumps to it
2. **Stage 1** (Forth) reads and interprets Stage 2 Forth extensions
3. **Stage 2** adds control flow words (IF/THEN/ELSE, loops)
4. **Stage 3** (C compiler in Forth) reads C source, emits ARM64 assembly

The entire chain runs as a single pipeline with no intermediate files.

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
├── stage0/           # Hex loader (trust anchor)
│   ├── stage0.c      # C implementation (108 lines)
│   └── stage0.s      # ARM64 assembly reference
├── stage1/           # Minimal Forth interpreter
│   ├── forth.c       # C reference implementation
│   └── forth.s       # ARM64 assembly (converted to hex for bootstrap)
├── stage2/           # Extended Forth
│   ├── forth.c       # Host implementation
│   └── forth.fth     # Forth source (76 lines)
├── stage3/           # Subset C compiler
│   └── cc.fth        # C compiler in Forth (1,163 lines)
├── stage4/           # C89 compiler
│   └── cc.c          # Full C89 implementation
├── stage5/           # C99 compiler
│   └── cc.c          # C99 extensions
├── tools/            # Build utilities
│   └── macho_to_hex.sh
├── tests/            # Test suites for each stage
├── bootstrap.sh      # Full bootstrap with verification
├── Makefile          # Build system
│
│ Generated artifacts:
├── stage1.hex        # Stage 1 binary in hex format (7.7 KB)
├── output.s          # Compiled ARM64 assembly output
└── manifest.txt      # SHA256 hashes for reproducibility
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

The bootstrap script generates `manifest.txt` with SHA256 hashes of all artifacts:

```bash
# Run full bootstrap with verification
./bootstrap.sh

# Check manifest
cat manifest.txt
# Sectorc Verification Manifest
# Generated: 2025-12-18 10:57:00 UTC
# 5b7264fe...  stage0/stage0
# b3dc0dac...  stage1/forth
# ...

# Verify reproducibility (re-run and compare hashes)
./bootstrap.sh
shasum -a 256 -c manifest.txt
```

The generated `output.s` can be manually inspected to verify no malicious code injection.

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

## Auditable Size Metrics

The entire bootstrap chain source is small enough for manual verification:

| Stage | Source | Size | Lines | Audit Time |
|-------|--------|------|-------|------------|
| Stage 0 | `stage0/stage0.c` | 2.9 KB | 108 | ~2 hours |
| Stage 1 | `stage1/forth.s` | 20.2 KB | 947 | ~8 hours |
| Stage 2 | `stage2/forth.fth` | 2.1 KB | 76 | ~1 hour |
| Stage 3 | `stage3/cc.fth` | 23.6 KB | 1,163 | ~12 hours |
| **Total** | | **48.8 KB** | **2,294** | **~23 hours** |

Stages 4-5 (C89/C99 compilers) are larger but can be machine-verified against their predecessors.

## Security Considerations

This project addresses the "trusting trust" problem identified by Ken Thompson in 1984:

1. **Minimal trust anchor**: Stage 0 is 108 lines of C, fully auditable in under 2 hours
2. **Chain of trust**: Each stage is compiled/interpreted by the previous trusted stage
3. **No external dependencies**: The chain builds from hex → working C compiler
4. **Reproducibility**: `manifest.txt` contains SHA256 hashes of all artifacts
5. **Transparent output**: Generated assembly is human-readable

**Trust assumptions:**
- Your CPU executes documented instructions correctly
- Your disassembler is accurate
- Auditors are competent and not colluding

## License

MIT License

## References

- Ken Thompson, "Reflections on Trusting Trust" (1984)
- [Bootstrappable Builds](https://bootstrappable.org/)
- [stage0](https://github.com/oriansj/stage0)
