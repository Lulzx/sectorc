# Trustworthy Bootstrap Chain - Linux i386

True "trusting trust" solution: hand-written hex all the way down.

## Architecture

```
Stage 0 (179 bytes)     Stage 1 (176 bytes)     Stage 2 (479 bytes)     Stage 3 (363 bytes)
+-----------------+    +------------------+    +------------------+    +---------------+
|   Hex Loader    |--->|   Hex to Binary  |--->|   Mini Forth     |--->|  C Compiler   |
| (executes hex)  |    | (outputs bytes)  |    | (stack machine)  |    | (compiles C)  |
+-----------------+    +------------------+    +------------------+    +---------------+
   hand-written           hand-written           hand-written           written in
      hex                    hex                    hex                  Forth (.s2)
```

**Total trust anchor: 834 bytes** - auditable in ~2 hours

## Quick Start (Linux i386)

```bash
# Run the complete bootstrap
./bootstrap.sh

# Or step by step:

# 1. Build Stage 0 from hex (using xxd as trust anchor)
grep -v '^\s*#' stage0.hex | sed 's/#.*//' | xxd -r -p > stage0 && chmod +x stage0

# 2. Build Stage 1 (hex2bin)
grep -v '^\s*#' stage1.hex | sed 's/#.*//' | xxd -r -p > hex2bin && chmod +x hex2bin

# 3. Build Stage 2 (Forth)
grep -v '^\s*#' stage2.hex | sed 's/#.*//' | xxd -r -p > forth && chmod +x forth

# 4. Build Stage 3 (C compiler) using Forth
./forth < cc.s2 > cc && chmod +x cc

# 5. Compile C programs!
echo "int main(){return 7;}" | ./cc > a.out && chmod +x a.out
./a.out; echo $?  # prints 7
```

## Files

| File | Binary Size | Description |
|------|-------------|-------------|
| `stage0.hex` | 179 bytes | Hex loader - executes hex as i386 code |
| `stage1.hex` | 176 bytes | Hex-to-binary converter (standalone ELF) |
| `stage2.hex` | 479 bytes | Mini Forth interpreter (standalone ELF) |
| `cc.s2` | 363 bytes | C compiler (written in Stage 2 language) |
| `hello.s2` | 121 bytes | Hello World ELF in Stage 2 language |

## Stage 0: Hex Loader

Reads hex from stdin, converts to machine code, executes it.

```bash
# Test: exit with code 42
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80 q" | ./stage0
echo $?  # 42
```

The 'q' character triggers execution. Supports both uppercase (A-F) and lowercase (a-f) hex digits.

## Stage 1: Hex-to-Binary

Converts hex input to binary output. Like `xxd -r -p` but in 176 bytes.

```bash
echo "48 69 0a" | ./hex2bin  # prints "Hi"
```

## Stage 2: Mini Forth

A minimal stack-based interpreter with these commands:

| Cmd | Stack Effect | Description |
|-----|--------------|-------------|
| 0-9 | ( -- n ) | Push number (multi-digit supported) |
| space/newline/tab | | End number, push to stack |
| + | ( a b -- a+b ) | Add |
| - | ( a b -- a-b ) | Subtract |
| * | ( a b -- a*b ) | Multiply |
| / | ( a b -- a/b ) | Divide |
| > | ( n -- ) | Emit low byte to stdout |
| d | ( n -- n n ) | Duplicate top of stack |
| x | ( n -- ) | Drop top of stack |
| s | ( a b -- b a ) | Swap top two items |
| @ | ( addr -- val ) | Fetch 32-bit value from address |
| ! | ( val addr -- ) | Store 32-bit value to address |
| H | ( -- addr ) | Push HERE pointer |
| , | ( val -- ) | Store to HERE, advance by 4 |
| # | | Comment (skip until newline) |
| q | | Quit interpreter |

### Example: Output bytes

```bash
# Output "Hi\n"
echo "72 > 105 > 10 > q" | ./forth
```

### Example: Build ELF

See `hello.s2` - a complete "Hello World" ELF binary written in Stage 2 language.

```bash
./forth < hello.s2 > hello && chmod +x hello && ./hello  # prints "Hello"
```

## Stage 3: C Compiler

The C compiler (`cc.s2`) is written in Stage 2's language. When processed by Forth,
it outputs a 363-byte ELF binary that compiles C source code.

Currently supports:
- `int main() { return N; }` where N is a single digit (0-9)

```bash
# Build the compiler
./forth < cc.s2 > cc && chmod +x cc

# Compile a program
echo "int main(){return 7;}" | ./cc > prog && chmod +x prog
./prog; echo $?  # prints 7
```

The generated executables are 96 bytes each - minimal ELF binaries that exit with the specified return code.

## Trust Chain

1. **You trust**: Your CPU, Linux kernel, `xxd` (trivial tool, or type bytes manually)
2. **Stage 0**: 179 bytes of documented hex - auditable in 20 minutes
3. **Stage 1**: 176 bytes of documented hex - auditable in 20 minutes
4. **Stage 2**: 479 bytes of documented hex - auditable in 60 minutes
5. **Stage 3+**: Built by previous stages, verifiable by testing

## Verification

Every byte is documented against:
- [ELF specification](https://refspecs.linuxfoundation.org/elf/elf.pdf)
- [Intel i386 instruction reference](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
- [Linux syscall numbers](https://chromium.googlesource.com/chromiumos/docs/+/master/constants/syscalls.md#x86-32_bit)

### Manual Verification

```bash
# Verify Stage 0 ELF header
xxd stage0 | head -4
# Should show: 7f 45 4c 46 (ELF magic) ...

# Disassemble any stage
objdump -d -M intel stage0
ndisasm -b 32 -o 0x54 -e 0x54 forth  # disassemble Forth code section
```

## Testing

```bash
# Test Stage 0: should exit with code 42
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80 q" | ./stage0
echo $?  # 42

# Test hex2bin
echo "48 69 0a" | ./hex2bin  # prints "Hi"

# Test Forth arithmetic
echo "2 3 + d q" | ./forth  # duplicates and prints result

# Test Forth emit
echo "72 > 105 > 10 > q" | ./forth  # prints "Hi\n"

# Test Hello World
./forth < hello.s2 > hello && chmod +x hello && ./hello  # prints "Hello"

# Test C compiler (all single digits)
for n in 0 1 2 3 4 5 6 7 8 9; do
  echo "int main(){return $n;}" | ./cc > test && chmod +x test
  ./test; echo "return $n: exit code $?"
done
```

## Why This Matters

Ken Thompson's "Reflections on Trusting Trust" (1984) showed that a compromised
compiler can perpetuate itself by injecting backdoors into its own recompilation.

This bootstrap chain provides an escape:
- Start with **834 bytes** of hand-auditable hex
- Build increasingly powerful tools
- Each stage is verified by the previous
- No binary blobs, no hidden code

## Requirements

- Linux (i386 or with 32-bit support)
- `xxd` (or manually enter bytes)
- `chmod` (set executable bit)
- Bash (for bootstrap.sh)

To run on 64-bit Linux:
```bash
# Install 32-bit libraries if needed
sudo apt install libc6-i386  # Debian/Ubuntu
```

To run on macOS (ARM or Intel):
```bash
# Use Docker with i386 emulation
docker run --rm -v $(pwd):/work -w /work i386/debian:bullseye-slim ./bootstrap.sh
```
