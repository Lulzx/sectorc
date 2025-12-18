#!/bin/bash
# Sectorc Bootstrap Script
# Builds and verifies the complete bootstrap chain

set -e

# Setup tools
MACHO_TO_HEX="./tools/macho_to_hex.sh"
chmod +x "$MACHO_TO_HEX"

echo "==========================================="
echo "Sectorc: Trustworthy Bootstrap Chain"
echo "==========================================="
echo ""

# Build host binaries for each stage so we can hash them in a manifest.
echo "=== Building Host Stage Binaries (for hashing) ==="
make -s all
echo "Host stage binaries built."
echo ""

# Stage 0: Hex Loader
echo "=== Stage 0: Building Hex Loader ==="
# We use the C version as the 'host' seed for this environment
make -s stage0
echo "Stage 0 built."
echo ""

# Stage 1: Minimal Forth
echo "=== Stage 1: Building Minimal Forth ==="
# Assemble to object file
as -arch arm64 -o stage1/forth.o stage1/forth.s
# Link to executable to resolve all relocations
# The code is PIC (uses adr for base address), so it can run at any address
ld -arch arm64 -e _main -o stage1/forth.exe stage1/forth.o \
   -L/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib -lSystem

# Convert to Hex (from the executable with resolved relocations)
echo "Converting Stage 1 to Hex..."
"$MACHO_TO_HEX" stage1/forth.exe > stage1.hex
echo "Stage 1 Hex created: $(wc -c < stage1.hex) bytes"
echo ""

# Stage 2 & 3: Run the Pipeline
echo "=== Stage 2 & 3: Running Bootstrap Pipeline ==="
echo "Pipeline: Stage 0 (Loader) <- Stage 1 (Hex) <- Stage 2 (Forth) <- Stage 3 (Compiler)"

# Combine inputs:
# 1. Stage 1 Hex (Forth Interpreter)
# 2. Separator '`' (triggers execution in stage0)
# 3. Stage 2 Source (Extended Forth)
# 4. Stage 3 Source (Compiler)
# 5. "RUN" command (if not at end of stage3)

# We expect Stage 3 to compile a tiny C program from stdin and output assembly.
(cat stage1.hex; printf "\x60"; cat stage2/forth.fth stage3/cc.fth; cat tests/stage3/hello.c) | ./stage0/stage0 > output.s

echo "Pipeline finished."
echo "Output size: $(wc -c < output.s) bytes"
echo ""

# Verify Output
echo "=== Verification ==="
echo "Checking generated assembly..."
if grep -q "_main:" output.s && grep -q "ret" output.s; then
    echo "SUCCESS: Valid assembly generated."
    head -n 10 output.s
else
    echo "FAILURE: Invalid output."
    cat output.s
    exit 1
fi

echo ""
echo "=== Manifest ==="
echo "Generating manifest.txt..."
{
  echo "# Sectorc Verification Manifest"
  echo "# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo ""
  shasum -a 256 stage0/stage0 stage1/forth stage2/forth stage3/cc stage4/cc stage5/cc stage1.hex output.s 2>/dev/null
} > manifest.txt
echo "Wrote manifest.txt"

echo ""
echo "==========================================="
echo "Bootstrap complete!"
echo "==========================================="
