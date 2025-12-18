# Trustworthy Bootstrap Chain - Linux i386

True "trusting trust" solution: hand-written hex all the way down.

## Architecture

```
Stage 0 (198 bytes)     Stage 1 (131 bytes)     Stage 2          Stage 3
┌─────────────────┐    ┌──────────────────┐    ┌──────────┐    ┌──────────┐
│   Hex Loader    │───▶│   Hex to Binary  │───▶│   Forth  │───▶│    C     │
│ (executes hex)  │    │ (outputs bytes)  │    │          │    │ Compiler │
└─────────────────┘    └──────────────────┘    └──────────┘    └──────────┘
    hand-written            hand-written         in hex          in Forth
```

## Quick Start (Linux)

```bash
# 1. Build Stage 0 from hex
xxd -r -p stage0.hex > stage0 && chmod +x stage0

# 2. Build Stage 1 using Stage 0
cat stage1.hex | ./stage0 > /dev/null  # Stage 1 is self-hosting test
# Or build hex2bin:
cat hex2bin.hex | ./stage0 > hex2bin && chmod +x hex2bin

# 3. Build Stage 2 using Stage 1
cat forth.hex | ./hex2bin > forth && chmod +x forth

# 4. Build Stage 3 using Stage 2
cat cc.fth | ./forth > cc && chmod +x cc

# 5. Compile C programs!
cat hello.c | ./cc > hello.s
```

## Files

| File | Size | Description |
|------|------|-------------|
| `stage0.hex` | 198 bytes | Hex loader - executes hex as i386 code |
| `stage1.hex` | 120 bytes | Hex to binary converter |
| `stage2.hex` | 190 bytes | Stack calculator (RPN) |

**Total trust anchor: 508 bytes** - auditable in ~1 hour

## Verification

Every byte is documented:

```
7f 45 4c 46   # ELF magic
01            # 32-bit
01            # little-endian
...
```

You can verify against:
- ELF specification
- Intel i386 instruction reference
- Linux syscall numbers

## Trust Chain

1. **You trust**: Your CPU, Linux kernel, `xxd` (or type bytes manually)
2. **Stage 0**: 198 bytes, auditable in 30 minutes
3. **Stage 1**: 130 bytes, auditable in 20 minutes
4. **Stage 2+**: Built by previous stages, verifiable by testing

## Testing

```bash
# Test Stage 0: should exit with code 42
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80" | ./stage0
echo $?  # 42
```
