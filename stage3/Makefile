# Stage 3: Subset C Compiler
# Compiles subset C to ARM64 assembly

CC = clang
CFLAGS = -O0 -Wall -Wextra -arch arm64

.PHONY: all clean test

all: cc

cc: cc.c
	$(CC) $(CFLAGS) -o cc cc.c

# Test compilation
test: cc
	@echo "=== Testing Stage 3 Compiler ==="
	@echo "--- Compiling test program ---"
	./cc ../tests/stage3/hello.c -o /tmp/hello.s
	@cat /tmp/hello.s
	@echo ""
	@echo "--- Assembling and linking ---"
	$(CC) -arch arm64 -o /tmp/hello /tmp/hello.s
	@echo "--- Running ---"
	@/tmp/hello; echo "Exit code: $$?"

clean:
	rm -f cc

size: cc
	@ls -la cc
	@size cc
