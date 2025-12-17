# Stage 1: Minimal Forth Interpreter
# Build the Forth system

CC = clang
AS = as

CFLAGS = -O0 -Wall -Wextra -arch arm64
ASFLAGS = -arch arm64

.PHONY: all clean test

all: forth

# Build Forth from C (primary, macOS compatible)
forth: forth.c
	$(CC) $(CFLAGS) -o forth forth.c

# Build from assembly (alternative, for reference)
forth-asm: forth-asm.o
	$(CC) $(CFLAGS) -o forth-asm forth-asm.o

forth-asm.o: forth.s
	$(AS) $(ASFLAGS) -o forth-asm.o forth.s

# Generate hex dump for loading via Stage 0
# (for verification purposes)
forth.hex: forth
	xxd -p forth > forth.hex

# Test the Forth interpreter
test: forth
	@echo "=== Testing Forth Interpreter ==="
	@echo "1 2 + . BYE" | ./forth
	@echo ""
	@echo "=== Interactive test ==="
	@echo "Type 'BYE' to exit"

clean:
	rm -f forth forth.o forth.hex

# Size check
size: forth
	@echo "=== Binary size ==="
	@ls -la forth
	@echo ""
	@size forth
