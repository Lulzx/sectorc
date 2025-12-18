# Stage 2: Extended Forth Interpreter
# Adds strings, file I/O, control flow, meta-compilation

CC = clang
CFLAGS = -O0 -Wall -Wextra -arch arm64

.PHONY: all clean test

all: forth

forth: forth.c
	$(CC) $(CFLAGS) -o forth forth.c

test: forth
	@echo "=== Testing Stage 2 Forth ==="
	@echo "1 2 + . BYE" | ./forth
	@echo ""
	@../tests/stage2/run_tests.sh ./forth

clean:
	rm -f forth

size: forth
	@ls -la forth
	@size forth
