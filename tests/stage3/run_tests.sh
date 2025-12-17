#!/bin/bash
# Stage 3 C Compiler test suite

CC="${1:-../../stage3/cc}"
PASSED=0
FAILED=0

test_c() {
    local name="$1"
    local expected="$2"
    local file="$3"

    echo -n "Testing: $name... "

    # Compile
    "$CC" "$file" -o /tmp/test.s 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "FAIL (compilation error)"
        ((FAILED++))
        return
    fi

    # Assemble and link
    clang -arch arm64 -o /tmp/test /tmp/test.s 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "FAIL (assembly error)"
        ((FAILED++))
        return
    fi

    # Run
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

echo "=== Stage 3 C Compiler Test Suite ==="
echo ""

test_c "hello (return 42)" 42 "hello.c"
test_c "arithmetic" 0 "arithmetic.c"
test_c "loops" 0 "loops.c"
test_c "functions" 0 "functions.c"

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
