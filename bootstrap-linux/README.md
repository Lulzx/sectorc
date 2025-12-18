# Trustworthy Bootstrap Chain - Linux i386

True "trusting trust" solution: hand-written hex all the way down.

## Architecture

```
Stage 0 (198 bytes)     Stage 1 (207 bytes)     Stage 2 (477 bytes)     Stage 3
+-----------------+    +------------------+    +------------------+    +----------+
|   Hex Loader    |--->|   Hex to Binary  |--->|   Mini Forth     |--->|    C     |
| (executes hex)  |    | (outputs bytes)  |    | (stack machine)  |    | Compiler |
+-----------------+    +------------------+    +------------------+    +----------+
   hand-written           hand-written           hand-written          in Forth
      hex                    hex                    hex                (.s2 file)
```

**Total trust anchor: 882 bytes** - auditable in ~2 hours

## Quick Start (Linux i386)

```bash
# Run the complete bootstrap
./bootstrap.sh

# Or step by step:

# 1. Build Stage 0 from hex (using xxd as trust anchor)
xxd -r -p <(grep -v '^#' stage0.hex | tr -d ' \n') > stage0 && chmod +x stage0

# 2. Build Stage 1 (hex2bin)
xxd -r -p <(grep -v '^#' stage1.hex | tr -d ' \n') > hex2bin && chmod +x hex2bin

# 3. Build Stage 2 (Forth) using hex2bin
grep -v '^#' stage2.hex | tr -d ' \n' | ./hex2bin > forth && chmod +x forth

# 4. Build Stage 3 (C compiler) using Forth
./forth < cc.s2 > cc && chmod +x cc

# 5. Compile C programs!
echo "int main(){return 42;}" | ./cc > a.out && chmod +x a.out
./a.out; echo $?  # prints 42
```

## Files

| File | Binary Size | Description |
|------|-------------|-------------|
| `stage0.hex` | 198 bytes | Hex loader - executes hex as i386 code |
| `stage1.hex` | 207 bytes | Hex-to-binary converter (standalone ELF) |
| `stage2.hex` | 477 bytes | Mini Forth interpreter (standalone ELF) |
| `cc.s2` | ~500 bytes | C compiler (written in Stage 2 language) |
| `hello.s2` | example | Hello World ELF in Stage 2 language |

## Stage 0: Hex Loader

Reads hex from stdin, converts to machine code, executes it.

```bash
# Test: exit with code 42
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80 q" | ./stage0
echo $?  # 42
```

The 'q' character triggers execution.

## Stage 1: Hex-to-Binary

Converts hex input to binary output. Like `xxd -r -p` but in 120 bytes.

```bash
echo "48 65 6c 6c 6f 0a" | ./hex2bin  # prints "Hello"
```

## Stage 2: Mini Forth

A minimal stack-based interpreter with these commands:

| Cmd | Stack Effect | Description |
|-----|--------------|-------------|
| 0-9 | ( -- n ) | Push number (multi-digit) |
| space | | End number, push to stack |
| + | ( a b -- a+b ) | Add |
| - | ( a b -- a-b ) | Subtract |
| * | ( a b -- a*b ) | Multiply |
| / | ( a b -- a/b ) | Divide |
| > | ( n -- ) | Emit byte to stdout |
| d | ( n -- n n ) | Duplicate |
| x | ( n -- ) | Drop |
| s | ( a b -- b a ) | Swap |
| @ | ( addr -- val ) | Fetch 32-bit |
| ! | ( val addr -- ) | Store 32-bit |
| H | ( -- addr ) | Push HERE pointer |
| , | ( val -- ) | Store to HERE, advance by 4 |
| q | | Quit |

### Example: Output bytes

```bash
# Output "Hi\n"
echo "72 > 105 > 10 > q" | ./forth
```

### Example: Build ELF

See `hello.s2` - a complete "Hello World" ELF binary written in Stage 2 language.

```bash
./forth < hello.s2 > hello && chmod +x hello && ./hello
```

## Stage 3: C Compiler

The C compiler (`cc.s2`) is written in Stage 2's language. When processed by Forth,
it outputs an ELF binary that compiles C source code.

Currently supports:
- `int main() { return N; }` where N is a single digit (0-9)

```bash
# Build the compiler
./forth < cc.s2 > cc && chmod +x cc

# Compile a program
echo "int main(){return 7;}" | ./cc > prog && chmod +x prog
./prog; echo $?  # prints 7
```

## Trust Chain

1. **You trust**: Your CPU, Linux kernel, `xxd` (trivial tool, or type bytes manually)
2. **Stage 0**: 198 bytes of documented hex - auditable in 30 minutes
3. **Stage 1**: 207 bytes of documented hex - auditable in 30 minutes
4. **Stage 2**: 477 bytes of documented hex - auditable in 60 minutes
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

# Disassemble Stage 0
objdump -d -M intel stage0
```

## Testing

```bash
# Test Stage 0: should exit with code 42
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80 q" | ./stage0
echo $?  # 42

# Test hex2bin
echo "48 69 0a" | ./hex2bin  # prints "Hi"

# Test Forth
echo "2 3 + > q" | ./forth | od -An -tu1  # prints "5"

# Test Hello World
./forth < hello.s2 > hello && chmod +x hello && ./hello  # prints "Hello"

# Test C compiler
echo "int main(){return 5;}" | ./cc > test && chmod +x test
./test; echo $?  # 5
```

## Why This Matters

Ken Thompson's "Reflections on Trusting Trust" (1984) showed that a compromised
compiler can perpetuate itself by injecting backdoors into its own recompilation.

This bootstrap chain provides an escape:
- Start with 647 bytes of hand-auditable hex
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
