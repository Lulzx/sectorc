#!/bin/bash
# Stage 1 Forth test suite

FORTH="${1:-../../stage1/forth}"
PASSED=0
FAILED=0

test_forth() {
    local name="$1"
    local expected="$2"
    local input="$3"

    echo -n "Testing: $name... "
    local actual=$(echo "$input" | "$FORTH" 2>&1 | tr -d '\n ')

    if [ "$actual" = "$expected" ]; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL (expected '$expected', got '$actual')"
        ((FAILED++))
    fi
}

echo "=== Stage 1 Forth Test Suite ==="
echo ""

# Basic arithmetic
echo "--- Arithmetic ---"
test_forth "addition" "3" "1 2 + . BYE"
test_forth "subtraction" "7" "10 3 - . BYE"
test_forth "multiplication" "42" "6 7 * . BYE"
test_forth "division" "5" "20 4 / . BYE"
test_forth "modulo" "1" "10 3 MOD . BYE"
test_forth "negative" "-5" "-5 . BYE"
test_forth "negate" "-42" "42 NEGATE . BYE"
test_forth "abs positive" "5" "5 ABS . BYE"
test_forth "abs negative" "5" "-5 ABS . BYE"
test_forth "1+" "6" "5 1+ . BYE"
test_forth "1-" "4" "5 1- . BYE"

# Stack operations
echo ""
echo "--- Stack Operations ---"
test_forth "DUP" "1010" "10 DUP . . BYE"
test_forth "DROP" "5" "5 10 DROP . BYE"
test_forth "SWAP" "510" "5 10 SWAP . . BYE"
test_forth "OVER" "5105" "5 10 OVER . . . BYE"
test_forth "ROT" "51510" "5 10 15 ROT . . . BYE"

# Comparison
echo ""
echo "--- Comparison ---"
test_forth "less than true" "-1" "5 10 < . BYE"
test_forth "less than false" "0" "10 5 < . BYE"
test_forth "greater than true" "-1" "10 5 > . BYE"
test_forth "greater than false" "0" "5 10 > . BYE"
test_forth "equal true" "-1" "5 5 = . BYE"
test_forth "equal false" "0" "5 10 = . BYE"
test_forth "not equal true" "-1" "5 10 <> . BYE"
test_forth "not equal false" "0" "5 5 <> . BYE"
test_forth "0= true" "-1" "0 0= . BYE"
test_forth "0= false" "0" "5 0= . BYE"

# Bitwise
echo ""
echo "--- Bitwise ---"
test_forth "AND" "8" "12 10 AND . BYE"
test_forth "OR" "14" "12 10 OR . BYE"
test_forth "XOR" "6" "12 10 XOR . BYE"
test_forth "LSHIFT" "40" "5 3 LSHIFT . BYE"
test_forth "RSHIFT" "2" "16 3 RSHIFT . BYE"

# I/O
echo ""
echo "--- I/O ---"
test_forth "EMIT" "A" "65 EMIT BYE"

# Complex expressions
echo ""
echo "--- Complex Expressions ---"
test_forth "complex 1" "25" "5 DUP * . BYE"
test_forth "complex 2" "14" "2 3 + 2 * 4 + . BYE"
test_forth "complex 3" "100" "10 10 * . BYE"

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
