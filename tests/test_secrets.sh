#!/bin/bash
# Secrets availability tests

test_secret() {
    local name="$1"
    local path="$2"

    if [[ -r "$path" ]]; then
        # Check it's not empty
        if [[ -s "$path" ]]; then
            pass "Secret $name: exists and readable"
        else
            fail "Secret $name: exists but empty"
        fi
    else
        fail "Secret $name: not found or not readable"
    fi
}

test_secret "anthropic_api_key" "/run/secrets/anthropic_api_key"
test_secret "github_token" "/run/secrets/github_token"
test_secret "ha_access_token" "/run/secrets/ha_access_token"
