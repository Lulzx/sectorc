#!/bin/bash
# Build Stage 0 from hex source
# No compiler, no assembler - just hex to binary conversion

set -e

# Strip comments and whitespace, convert to binary
grep -v '^#' stage0.hex | tr -d ' \n' | xxd -r -p > stage0
chmod +x stage0

# Show size
SIZE=$(wc -c < stage0)
echo "Stage 0 built: $SIZE bytes"

# Verify it's a valid ELF
file stage0
