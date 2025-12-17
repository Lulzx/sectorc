# Stage 5: C99 Compiler
# C99 features: // comments, _Bool, inline, restrict, for-loop declarations

CC = clang
CFLAGS = -O0 -Wall -Wextra -arch arm64

.PHONY: all clean test

all: cc

cc: cc.c
	$(CC) $(CFLAGS) -o cc cc.c

test: cc
	@echo "=== Testing Stage 5 Compiler ==="
	./cc ../tests/stage3/hello.c -o /tmp/test.s
	clang -arch arm64 -o /tmp/test /tmp/test.s
	@/tmp/test; echo "Hello test: $$?"

clean:
	rm -f cc
