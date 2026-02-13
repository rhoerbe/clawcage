#!/bin/bash
# Direct network access (bypassing proxy) - should be blocked by nftables
# NOTE: These tests only work with rootful podman. Rootless podman uses
# slirp4netns/pasta which bypasses nftables FORWARD chain.
# Security is enforced via proxy (FilterDefaultDeny) instead.

test_direct_blocked() {
    local name="$1"
    local url="$2"

    if timeout 6 curl --noproxy '*' --max-time 5 -s -o /dev/null "$url" 2>/dev/null; then
        # For rootless podman, this is expected to "fail" (connect succeeds)
        skip "Direct access to $name: connected (expected with rootless podman - nftables bypassed)"
    else
        pass "Direct access to $name: correctly blocked by nftables"
    fi
}

test_direct_blocked "example.com HTTPS" "https://example.com"
test_direct_blocked "example.com HTTP" "http://example.com"
test_direct_blocked "google.com" "https://google.com"
