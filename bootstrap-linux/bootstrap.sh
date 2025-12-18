#!/bin/bash
# Trustworthy Bootstrap - Linux i386
# No make, no clang, no gcc - just xxd and shell
set -e

echo "=== Trustworthy Bootstrap Chain ==="
echo ""

# Stage 0: Hex loader (198 bytes)
echo "Stage 0: Building hex loader from documented hex..."
xxd -r -p stage0.hex > stage0
chmod +x stage0
echo "  size: $(wc -c < stage0) bytes"
file stage0

# Stage 1: Hex-to-binary (118 bytes)
echo ""
echo "Stage 1: Building hex2bin using Stage 0..."
cat stage1.hex | ./stage0 > hex2bin
chmod +x hex2bin
echo "  size: $(wc -c < hex2bin) bytes"

# Verification tests
echo ""
echo "=== Verification ==="

echo -n "Test Stage 0 (exit 42): "
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80" | ./stage0 && echo "FAIL" || [ $? -eq 42 ] && echo "PASS"

echo -n "Test Stage 1 (hex2bin): "
RESULT=$(echo "48 69 0a" | ./hex2bin)
[ "$RESULT" = $'Hi\n' ] && echo "PASS" || echo "FAIL (got: $RESULT)"

echo ""
echo "=== Bootstrap Summary ==="
echo "Stage 0: 198 bytes (hex loader, executes hex as i386 code)"
echo "Stage 1: 118 bytes (hex2bin, outputs binary from hex)"
echo ""
echo "Trust anchor total: 316 bytes of hand-written, documented hex"
echo ""
echo "Next: Use Stage 1 to build a Forth interpreter or C compiler"
