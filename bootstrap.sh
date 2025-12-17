#!/bin/bash
# Sectorc Bootstrap Script
# Builds and verifies the complete bootstrap chain

set -e

echo "==========================================="
echo "Sectorc: Trustworthy Bootstrap Chain"
echo "==========================================="
echo ""

# Stage 0: Hex Loader
echo "=== Stage 0: Building Hex Loader ==="
make -C stage0 clean
make -C stage0
echo "Stage 0 complete."
echo ""

# Stage 1: Minimal Forth
echo "=== Stage 1: Building Minimal Forth ==="
make -C stage1 clean
make -C stage1
echo "Stage 1 complete."
echo ""

# Stage 2: Extended Forth
echo "=== Stage 2: Building Extended Forth ==="
make -C stage2 clean
make -C stage2
echo "Stage 2 complete."
echo ""

# Stage 3: Subset C Compiler
echo "=== Stage 3: Building Subset C Compiler ==="
make -C stage3 clean
make -C stage3
echo "Stage 3 complete."
echo ""

# Stage 4: C89 Compiler
echo "=== Stage 4: Building C89 Compiler ==="
make -C stage4 clean
make -C stage4
echo "Stage 4 complete."
echo ""

# Stage 5: C99 Compiler
echo "=== Stage 5: Building C99 Compiler ==="
make -C stage5 clean
make -C stage5
echo "Stage 5 complete."
echo ""

# Generate verification hashes
echo "=== Generating Verification Hashes ==="
echo "# Sectorc Verification Manifest" > manifest.txt
echo "# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> manifest.txt
echo "" >> manifest.txt
shasum -a 256 stage0/stage0 >> manifest.txt 2>/dev/null || echo "stage0/stage0 not found"
shasum -a 256 stage1/forth >> manifest.txt 2>/dev/null || echo "stage1/forth not found"
shasum -a 256 stage2/forth >> manifest.txt 2>/dev/null || echo "stage2/forth not found"
shasum -a 256 stage3/cc >> manifest.txt 2>/dev/null || echo "stage3/cc not found"
shasum -a 256 stage4/cc >> manifest.txt 2>/dev/null || echo "stage4/cc not found"
shasum -a 256 stage5/cc >> manifest.txt 2>/dev/null || echo "stage5/cc not found"
cat manifest.txt
echo ""

echo "==========================================="
echo "Bootstrap complete!"
echo "==========================================="
