#!/bin/bash
# Proxy - blocked domains tests

test_url_blocked() {
    local name="$1"
    local url="$2"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)

    # Expect 403 (proxy denies) or 000 (connection failed)
    if [[ "$code" == "403" || "$code" == "000" ]]; then
        pass "Proxy blocks $name (HTTP $code)"
    else
        fail "Proxy allows $name unexpectedly (HTTP $code)"
    fi
}

test_url_blocked "example.com" "https://example.com"
test_url_blocked "google.com" "https://google.com"
test_url_blocked "reddit.com" "https://reddit.com"
