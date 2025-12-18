# Stage 0: ARM64 macOS Hex Loader
# Build the minimal hex loader

CC = clang
AS = as
LD = ld

# Use C version for Apple Silicon compatibility with JIT
# The assembly version (stage0.s) is kept for reference and audit

CFLAGS = -O0 -Wall -Wextra -arch arm64

.PHONY: all clean test size

all: stage0

# Primary build: C version with proper macOS JIT support
stage0: stage0.c
	$(CC) $(CFLAGS) -o stage0 stage0.c

# Alternative: assembly version (requires signing with JIT entitlements)
stage0-asm: stage0.o
	$(LD) -arch arm64 -e _start -lSystem -o stage0-asm stage0.o
	codesign -s - stage0-asm

stage0.o: stage0.s
	$(AS) -arch arm64 -o stage0.o stage0.s

# Show binary size (target: ~512 bytes for code section)
size: stage0
	@echo "=== Binary size breakdown ==="
	@size stage0
	@echo ""
	@echo "=== Total file size ==="
	@ls -l stage0 | awk '{print $$5 " bytes"}'
	@echo ""
	@echo "=== Code section size (target: ~512 bytes) ==="
	@otool -l stage0 | awk '$$1=="sectname" && $$2=="__text"{seen_text=1} seen_text && $$1=="size"{print $$0; exit}' || echo "Use otool -l stage0 for details"

# Test with a simple exit code program
test: stage0
	@echo "=== Test 1: Exit with code 42 ==="
	@echo "d2800540 d2800020 d4001001" | ./stage0; \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -eq 42 ]; then \
		echo "PASS: Exit code 42"; \
	else \
		echo "FAIL: Expected 42, got $$EXIT_CODE"; \
	fi
	@echo ""
	@echo "=== Test 2: Exit with code 0 ==="
	@echo "d2800000 d2800020 d4001001" | ./stage0; \
	EXIT_CODE=$$?; \
	if [ $$EXIT_CODE -eq 0 ]; then \
		echo "PASS: Exit code 0"; \
	else \
		echo "FAIL: Expected 0, got $$EXIT_CODE"; \
	fi

clean:
	rm -f stage0 stage0.o

# Disassemble for verification
disasm: stage0
	otool -tv stage0
