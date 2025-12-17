#!/bin/bash
# Stage 2 Forth test suite

FORTH="${1:-../../stage2/forth}"
PASSED=0
FAILED=0

test_forth() {
    local name="$1"
    local expected="$2"
    local input="$3"

    echo -n "Testing: $name... "
    local actual=$(echo "$input" | "$FORTH" 2>&1 | tr -d '\n')

    # Trim leading/trailing whitespace for comparison
    expected=$(echo "$expected" | xargs)
    actual=$(echo "$actual" | xargs)

    if [ "$actual" = "$expected" ]; then
        echo "PASS"
        ((PASSED++))
    else
        echo "FAIL (expected '$expected', got '$actual')"
        ((FAILED++))
    fi
}

echo "=== Stage 2 Forth Test Suite ==="
echo ""

# Stage 1 compatibility
echo "--- Stage 1 Compatibility ---"
test_forth "addition" "3" "1 2 + . BYE"
test_forth "subtraction" "7" "10 3 - . BYE"
test_forth "multiplication" "42" "6 7 * . BYE"
test_forth "division" "5" "20 4 / . BYE"

# Extended arithmetic
echo ""
echo "--- Extended Arithmetic ---"
test_forth "MIN" "5" "5 10 MIN . BYE"
test_forth "MAX" "10" "5 10 MAX . BYE"
test_forth "/MOD" "3 1" "10 3 /MOD . . BYE"
test_forth "2*" "20" "10 2* . BYE"
test_forth "2/" "5" "10 2/ . BYE"
test_forth "CELLS" "16" "2 CELLS . BYE"

# Extended stack
echo ""
echo "--- Extended Stack ---"
test_forth "DEPTH" "3" "1 2 3 DEPTH . BYE"
test_forth "PICK" "1" "1 2 3 2 PICK . BYE"
test_forth "?DUP nonzero" "5 5" "5 ?DUP . . BYE"
test_forth "?DUP zero" "0" "0 ?DUP . BYE"

# Strings
echo ""
echo "--- Strings ---"
test_forth "S\" TYPE" "Hello" 'S" Hello" TYPE BYE'
test_forth ".\"" "Hello" '." Hello" BYE'

# Number bases
echo ""
echo "--- Number Bases ---"
test_forth "hex literal" "255" '$FF . BYE'
test_forth "decimal literal" "10" '#10 . BYE'
test_forth "binary literal" "5" '%101 . BYE'

# Conditional compilation
echo ""
echo "--- Conditional Compilation ---"
test_forth "[IF] true" "YES" '1 [IF] ." YES" [THEN] BYE'
test_forth "[IF] false" "" '0 [IF] ." NO" [THEN] BYE'
test_forth "[IF] [ELSE]" "ELSE" '0 [IF] ." IF" [ELSE] ." ELSE" [THEN] BYE'

# Comments
echo ""
echo "--- Comments ---"
test_forth "backslash comment" "5" '5 \ this is a comment
. BYE'
test_forth "paren comment" "5" '5 ( this is a comment ) . BYE'

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
