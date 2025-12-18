#!/bin/bash
# Trustworthy Bootstrap Chain - Linux i386
# No make, no clang, no gcc - just xxd and shell
#
# Trust hierarchy:
#   - xxd: trivial hex-to-binary tool (or use printf/manual entry)
#   - 647 bytes of hand-written, documented hex
#   - Each stage builds the next

set -e
cd "$(dirname "$0")"

echo "=== Trustworthy Bootstrap Chain ==="
echo ""

# Helper to extract pure hex (strip comments, including inline comments)
strip_hex() {
    grep -v '^\s*#' "$1" | sed 's/#.*//' | tr -d ' \n\t'
}

# Stage 0: Hex loader (198 bytes)
# This is the trust anchor - every byte is documented
echo "Stage 0: Building hex loader from documented hex..."
strip_hex stage0.hex | xxd -r -p > stage0
chmod +x stage0
SIZE0=$(wc -c < stage0 | tr -d ' ')
echo "  Created: stage0 ($SIZE0 bytes)"

# Stage 1: Hex-to-binary filter (120 bytes)
# Built using xxd (could also use Stage 0 with creative piping)
echo ""
echo "Stage 1: Building hex2bin from documented hex..."
strip_hex stage1.hex | xxd -r -p > hex2bin
chmod +x hex2bin
SIZE1=$(wc -c < hex2bin | tr -d ' ')
echo "  Created: hex2bin ($SIZE1 bytes)"

# Stage 2: Mini Forth interpreter (329 bytes)
# Now we can use hex2bin!
echo ""
echo "Stage 2: Building Forth interpreter using hex2bin..."
strip_hex stage2.hex | ./hex2bin > forth
chmod +x forth
SIZE2=$(wc -c < forth | tr -d ' ')
echo "  Created: forth ($SIZE2 bytes)"

# Stage 3: C compiler
# Built by running Stage 2 Forth on cc.s2
echo ""
echo "Stage 3: Building C compiler using Forth..."
./forth < cc.s2 > cc
chmod +x cc
SIZE3=$(wc -c < cc | tr -d ' ')
echo "  Created: cc ($SIZE3 bytes)"

echo ""
echo "=== Verification Tests ==="

# Test Stage 0: Run hex that exits with 42
echo -n "Test Stage 0 (execute hex, exit 42): "
RESULT=$(echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80 q" | ./stage0; echo $?)
if [ "$RESULT" = "42" ]; then
    echo "PASS"
else
    echo "FAIL (expected 42, got $RESULT)"
fi

# Test hex2bin: Convert "48 69 0a" to "Hi\n"
echo -n "Test Stage 1 (hex2bin 'Hi'): "
RESULT=$(echo "48 69 0a" | ./hex2bin)
if [ "$RESULT" = $'Hi' ]; then
    echo "PASS"
else
    echo "FAIL (got: '$RESULT')"
fi

# Test Forth: Simple arithmetic
echo -n "Test Stage 2 (Forth 2+3): "
RESULT=$(echo "2 3 + > q" | ./forth | od -An -tu1 | tr -d ' \n')
if [ "$RESULT" = "5" ]; then
    echo "PASS"
else
    echo "FAIL (got: '$RESULT')"
fi

# Test hello.s2
echo -n "Test hello.s2 (Hello World ELF): "
./forth < hello.s2 > hello
chmod +x hello
RESULT=$(./hello 2>&1 || true)
if [ "$RESULT" = "Hello" ]; then
    echo "PASS"
else
    echo "FAIL (got: '$RESULT')"
fi

# Test C compiler
echo -n "Test Stage 3 (compile 'return 7'): "
echo "int main(){return 7;}" | ./cc > test_prog
chmod +x test_prog
./test_prog || EXITCODE=$?
if [ "$EXITCODE" = "7" ]; then
    echo "PASS"
else
    echo "FAIL (expected exit 7, got $EXITCODE)"
fi

echo ""
echo "=== Bootstrap Summary ==="
echo "Stage 0: $SIZE0 bytes (hex loader - executes hex as i386 code)"
echo "Stage 1: $SIZE1 bytes (hex2bin - converts hex to binary)"
echo "Stage 2: $SIZE2 bytes (Forth - stack-based interpreter)"
echo "Stage 3: $SIZE3 bytes (C compiler - compiles to ELF)"
echo ""
TOTAL=$((SIZE0 + SIZE1 + SIZE2))
echo "Trust anchor: $TOTAL bytes of hand-written, documented hex"
echo ""
echo "Bootstrap chain complete!"
echo "  xxd -> stage0.hex -> stage0"
echo "  xxd -> stage1.hex -> hex2bin"
echo "  hex2bin + stage2.hex -> forth"
echo "  forth + cc.s2 -> cc"
echo "  cc + source.c -> executable"
