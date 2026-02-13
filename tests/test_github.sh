#!/bin/bash
# GitHub CLI access tests

# Set up GitHub token from secret
if [[ -r /run/secrets/github_token ]]; then
    export GITHUB_TOKEN=$(cat /run/secrets/github_token)
fi

# Test 1: List issues
if gh issue list --repo rhoerbe/EU23_admin --limit 5 >/dev/null 2>&1; then
    pass "GitHub: list issues"
else
    fail "GitHub: list issues failed"
fi

# Test 2: View specific issue
if gh issue view 10 --repo rhoerbe/EU23_admin --json title >/dev/null 2>&1; then
    pass "GitHub: view issue #10"
else
    fail "GitHub: view issue #10 failed"
fi

# Test 3: Check repo access
if gh repo view rhoerbe/EU23_admin --json name >/dev/null 2>&1; then
    pass "GitHub: repo access"
else
    fail "GitHub: repo access failed"
fi
