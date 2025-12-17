# Stage 4: C89 Compiler
# Full C89 support with struct/union/enum/switch

CC = clang
CFLAGS = -O0 -Wall -Wextra -arch arm64

.PHONY: all clean test self-host

all: cc

cc: cc.c
	$(CC) $(CFLAGS) -o cc cc.c

test: cc
	@echo "=== Testing Stage 4 Compiler ==="
	./cc ../tests/stage3/hello.c -o /tmp/test.s
	clang -arch arm64 -o /tmp/test /tmp/test.s
	@/tmp/test; echo "Exit code: $$?"
	./cc ../tests/stage3/arithmetic.c -o /tmp/test.s
	clang -arch arm64 -o /tmp/test /tmp/test.s
	@/tmp/test; echo "Arithmetic test: $$?"
	./cc ../tests/stage3/functions.c -o /tmp/test.s
	clang -arch arm64 -o /tmp/test /tmp/test.s
	@/tmp/test; echo "Functions test: $$?"

# Self-hosting test: compile cc.c with itself
self-host: cc
	@echo "=== Self-hosting test ==="
	./cc cc.c -o /tmp/cc2.s
	clang -arch arm64 -o /tmp/cc2 /tmp/cc2.s
	@echo "Stage 4 compiler compiled itself!"

clean:
	rm -f cc
