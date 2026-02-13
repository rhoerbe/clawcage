#!/bin/bash
# Main test runner - executes inside container

TESTS_DIR="$(dirname "$0")"
PASSED=0
FAILED=0
ERRORS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ERRORS+=("$1")
    FAILED=$((FAILED + 1))
}

skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

echo "========================================"
echo "Agent Container Integration Tests"
echo "========================================"
echo ""

# Run individual test scripts
for test_script in "$TESTS_DIR"/test_*.sh; do
    if [[ -x "$test_script" ]]; then
        echo "--- Running $(basename "$test_script") ---"
        source "$test_script"
        echo ""
    fi
done

# Summary
echo "========================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "========================================"

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

exit 0
