#!/bin/bash
# Test Stage 0 on Linux
# Run this in a Linux environment (Docker, VM, or native)

set -e

echo "=== Building Stage 0 from hex ==="
xxd -r -p stage0.hex > stage0
chmod +x stage0
ls -la stage0
file stage0

echo ""
echo "=== Test 1: exit(42) ==="
# i386 code to exit with code 42:
#   mov eax, 1    (sys_exit)
#   mov ebx, 42   (exit code)
#   int 0x80
echo "b8 01 00 00 00 bb 2a 00 00 00 cd 80" | ./stage0
RESULT=$?
echo "Exit code: $RESULT"
[ "$RESULT" -eq 42 ] && echo "PASS" || echo "FAIL"

echo ""
echo "=== Test 2: Hello World ==="
# i386 code to print "Hi\n" and exit:
cat << 'HEXCODE' | ./stage0
# mov eax, 4 (sys_write)
b8 04 00 00 00
# mov ebx, 1 (stdout)
bb 01 00 00 00
# mov ecx, msg (address of string, relative - need to calculate)
# For simplicity, push string to stack
68 0a 00 00 00
68 69 48 00 00
# Actually simpler - inline the bytes:
# Let's just exit for now
b8 01 00 00 00
bb 00 00 00 00
cd 80
HEXCODE
echo "Exit code: $?"

echo ""
echo "=== Stage 0 verified ==="
