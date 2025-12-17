#!/bin/bash
# Stage 5: C99 Compiler Tests

CC="../../stage5/cc"
CLANG="clang"
CLANG_FLAGS="-arch arm64"

PASSED=0
FAILED=0

run_test() {
    local name=$1
    local source=$2
    local expected=$3

    echo -n "Testing $name... "

    # Compile with Stage 5 compiler
    $CC "$source" -o /tmp/test.s 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "FAILED (compilation error)"
        FAILED=$((FAILED + 1))
        return
    fi

    # Assemble with clang
    $CLANG $CLANG_FLAGS -o /tmp/test /tmp/test.s 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "FAILED (assembly error)"
        FAILED=$((FAILED + 1))
        return
    fi

    # Run and check result
    /tmp/test
    local result=$?

    if [ "$result" -eq "$expected" ]; then
        echo "PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "FAILED (expected $expected, got $result)"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== Stage 5 C99 Compiler Tests ==="
echo ""

# C99 feature tests
run_test "C99 comments" "c99_comments.c" 0
run_test "C99 _Bool type" "c99_bool.c" 0
run_test "C99 for-loop declaration" "c99_for_decl.c" 0
run_test "C99 inline functions" "c99_inline.c" 0

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

# Clean up
rm -f /tmp/test.s /tmp/test

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
