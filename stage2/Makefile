# Stage 2: Extended Forth Interpreter
# Adds strings, file I/O, control flow, meta-compilation

CC = clang
CFLAGS = -O0 -Wall -Wextra -arch arm64

.PHONY: all clean test

all: forth

forth:
	@if [ -f forth.c ]; then \
		$(CC) $(CFLAGS) -o forth forth.c; \
	else \
		test -x forth || (echo "stage2/forth.c missing and stage2/forth not present" >&2; exit 1); \
	fi

test: forth
	@echo "=== Testing Stage 2 Forth ==="
	@echo "1 2 + . BYE" | ./forth
	@echo ""
	@../tests/stage2/run_tests.sh ./forth

clean:
	@if [ -f forth.c ]; then rm -f forth; fi

size: forth
	@ls -la forth
	@size forth
