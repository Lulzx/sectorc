#!/bin/bash
INPUT="$1"

if [ -z "$INPUT" ]; then
    echo "Usage: $0 <macho-binary>"
    exit 1
fi

OFFSET=$(otool -l "$INPUT" | grep -A 5 "sectname __text" | grep offset | head -1 | awk '{print $2}')
SIZE_HEX=$(otool -l "$INPUT" | grep -A 5 "sectname __text" | grep size | head -1 | awk '{print $2}')
SIZE=$(($SIZE_HEX))

dd if="$INPUT" bs=1 skip="$OFFSET" count="$SIZE" 2>/dev/null | xxd -p | tr -d '\n'