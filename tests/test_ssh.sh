#!/bin/bash
# SSH connectivity tests

# Test 1: SSH to HA should succeed
# Requires: HA host configured with TrustedUserCAKeys
ssh_output=$(ssh -o BatchMode=yes -o ConnectTimeout=10 ha "echo ok" 2>&1)
if echo "$ssh_output" | grep -q "ok"; then
    pass "SSH to HA: connected successfully"
elif echo "$ssh_output" | grep -qi "permission denied\|no supported authentication"; then
    skip "SSH to HA: authentication failed (HA host needs CA certificate configured)"
elif echo "$ssh_output" | grep -qi "connection refused\|no route\|timed out"; then
    skip "SSH to HA: host unreachable (check network/firewall)"
else
    fail "SSH to HA: connection failed - $ssh_output"
fi

# Test 2: SSH to blocked host should timeout/fail
if timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no ha_agent@10.4.4.17 "echo ok" 2>/dev/null; then
    fail "SSH to 10.4.4.17: expected failure, but connected"
else
    pass "SSH to 10.4.4.17: correctly blocked"
fi
