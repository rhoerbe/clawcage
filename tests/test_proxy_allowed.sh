#!/bin/bash
# Proxy - allowed domains tests

test_url_allowed() {
    local name="$1"
    local url="$2"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null)

    # Accept 200, 301, 302, 400, 401, 403 as "reachable" (not proxy-blocked)
    if [[ "$code" =~ ^(200|301|302|400|401|403|404)$ ]]; then
        pass "Proxy allows $name (HTTP $code)"
    else
        fail "Proxy blocks $name unexpectedly (HTTP $code)"
    fi
}

test_url_allowed "GitHub API" "https://api.github.com"
test_url_allowed "GitHub raw" "https://raw.githubusercontent.com/robots.txt"
test_url_allowed "Anthropic API" "https://api.anthropic.com"
test_url_allowed "npmjs registry" "https://registry.npmjs.org"
test_url_allowed "HA direct" "http://10.4.4.10:8123"
