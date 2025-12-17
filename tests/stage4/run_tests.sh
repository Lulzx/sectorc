#!/bin/bash
# Stage 4 C89 Compiler test suite

CC="${1:-../../stage4/cc}"
PASSED=0
FAILED=0

test_c() {
    local name="$1"
    local expected="$2"
    local file="$3"

    echo -n "Testing: $name... "

    "$CC" "$file" -o /tmp/test.s 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "FAIL (compilation error)"
        ((FAILED++))
        return
    fi

    clang -arch arm64 -o /tmp/test /tmp/test.s 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "FAIL (assembly error)"
        ((FAILED++))
        return
    fi

    /tmp/test
    local actual=$?

    if [ "$actual" -eq "$expected" ]; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL (expected $expected, got $actual)"
        ((FAILED++))
    fi
}

echo "=== Stage 4 C89 Compiler Test Suite ==="
echo ""

# Stage 3 compatibility tests
test_c "hello" 42 "../stage3/hello.c"
test_c "arithmetic" 0 "../stage3/arithmetic.c"
test_c "loops" 0 "../stage3/loops.c"
test_c "functions" 0 "../stage3/functions.c"

# Stage 4 specific tests
test_c "switch" 0 "switch.c"
test_c "enum" 0 "enum.c"

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed."
    exit 1
fi
