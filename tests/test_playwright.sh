#!/bin/bash
# Playwright / HA Web UI tests
# Note: Full Playwright tests require MCP server. This tests basic reachability.

# Test HA landing page is reachable
http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://10.4.4.10:8123 2>/dev/null)

if [[ "$http_code" == "200" ]]; then
    pass "HA web UI: reachable (HTTP $http_code)"
else
    fail "HA web UI: not reachable (HTTP $http_code)"
fi

# Test that Playwright/Chromium is available
if npx playwright --version >/dev/null 2>&1; then
    pass "Playwright: installed and available"
else
    fail "Playwright: not available"
fi
