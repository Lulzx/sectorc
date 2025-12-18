# Stage 0: True Trust Anchor

**198 bytes** - Small enough to verify with a hex editor.

This is a hand-written ELF binary. No compiler. No assembler. Just documented bytes.

## What It Does

1. Allocates 64KB of executable memory (mmap)
2. Reads ASCII hex pairs from stdin
3. Converts to binary, stores in buffer
4. On EOF, jumps to the buffer and executes it

## Build

```bash
# Convert hex to binary (only tool needed: xxd)
xxd -r -p stage0.hex > stage0
chmod +x stage0
```

## Test

```bash
# This hex = exit(42) in i386
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80" | ./stage0
echo $?  # prints 42
```

## Verify

Every byte is documented in `stage0.hex`:

```
7f 45 4c 46   # ELF magic
01            # 32-bit
01            # little-endian
...
```

You can verify each byte against the ELF specification and i386 instruction set manual.

## Platform

- **Linux i386** (32-bit x86)
- Works on x86-64 Linux with 32-bit support
- Requires: `xxd` (part of vim) or any hex-to-binary converter

## Why 32-bit?

ELF32 headers are smaller than ELF64:
- ELF32 header: 52 bytes
- ELF32 program header: 32 bytes
- Total overhead: 84 bytes

This leaves 114 bytes for the actual hex loader code.

## Trust Model

This is the **only binary you need to trust**. Everything else bootstraps from here:

```
stage0.hex (198 bytes, human-readable)
    ↓ xxd
stage0 (198 bytes binary, runs hex loader)
    ↓ loads
stage1.hex (Forth interpreter)
    ↓ interprets
stage2.fth, stage3.fth (C compiler)
    ↓ compiles
your_program.c
```

## Audit Checklist

- [ ] Verify ELF header fields (bytes 0-51)
- [ ] Verify program header (bytes 52-83)
- [ ] Trace mmap syscall setup (bytes 84-113)
- [ ] Trace read loop logic (bytes 114-165)
- [ ] Trace hex conversion (bytes 166-179)
- [ ] Verify jump to buffer (bytes 180-182)

Time to audit: ~30 minutes for someone familiar with x86 assembly.
