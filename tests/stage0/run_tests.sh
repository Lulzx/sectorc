#!/bin/bash
# Stage 0 test suite

STAGE0="${1:-../../stage0/stage0}"
PASSED=0
FAILED=0

test_case() {
    local name="$1"
    local expected="$2"
    local input="$3"

    echo -n "Testing: $name... "
    echo -e "$input" | "$STAGE0"
    local actual=$?

    if [ "$actual" -eq "$expected" ]; then
        echo "PASS (exit code $actual)"
        ((PASSED++))
    else
        echo "FAIL (expected $expected, got $actual)"
        ((FAILED++))
    fi
}

echo "=== Stage 0 Test Suite ==="
echo ""

# Test exit codes
test_case "exit(0)" 0 "00 00 80 d2 30 00 80 d2 01 10 00 d4"
test_case "exit(42)" 42 "40 05 80 d2 30 00 80 d2 01 10 00 d4"
test_case "exit(1)" 1 "20 00 80 d2 30 00 80 d2 01 10 00 d4"
test_case "exit(255)" 255 "e0 1f 80 d2 30 00 80 d2 01 10 00 d4"

# Test whitespace handling
test_case "whitespace (spaces)" 42 "40 05 80 d2   30 00 80 d2   01 10 00 d4"
test_case "whitespace (tabs)" 42 "40\t05\t80\td2\t30\t00\t80\td2\t01\t10\t00\td4"
test_case "whitespace (newlines)" 42 "40 05 80 d2\n30 00 80 d2\n01 10 00 d4"

# Test comments
test_case "comment (hash)" 42 "# comment\n40 05 80 d2 30 00 80 d2 01 10 00 d4"
test_case "comment (semicolon)" 42 "; comment\n40 05 80 d2 30 00 80 d2 01 10 00 d4"
test_case "inline comment" 42 "40 05 80 d2 ; this is x0\n30 00 80 d2 # this is x16\n01 10 00 d4"

# Test case insensitivity
test_case "uppercase" 42 "40 05 80 D2 30 00 80 D2 01 10 00 D4"
test_case "mixed case" 42 "40 05 80 D2 30 00 80 d2 01 10 00 D4"

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
