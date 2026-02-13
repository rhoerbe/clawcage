# Integration Tests for Agent Container

Test harness to verify that allowed operations succeed and blocked operations fail.

## Test Environment

- **Host**: riva (local execution only)
- **Target**: Real HA host (10.4.4.10)
- **Secrets**: Real secrets (provisioned to ha_agent)
- **Network**: ha-agent-net with tinyproxy and nftables active

## Test Categories

### 1. SSH Connectivity

| Test | Command | Expected |
|------|---------|----------|
| SSH to HA allowed | `ssh ha "echo ok"` | Exit 0, output "ok" |
| SSH to other host blocked | `ssh -o ConnectTimeout=5 ha_agent@10.4.4.17` | Connection timeout/refused |

### 2. Proxy - Allowed Domains

| Test | Command | Expected |
|------|---------|----------|
| GitHub API | `curl -s -o /dev/null -w "%{http_code}" https://api.github.com` | 200 |
| GitHub raw content | `curl -s -o /dev/null -w "%{http_code}" https://raw.githubusercontent.com` | 200 or 400 |
| Anthropic API | `curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com` | 200 or 401 |
| npmjs | `curl -s -o /dev/null -w "%{http_code}" https://registry.npmjs.org` | 200 |
| HA direct | `curl -s -o /dev/null -w "%{http_code}" http://10.4.4.10:8123` | 200 |

### 3. Proxy - Blocked Domains

| Test | Command | Expected |
|------|---------|----------|
| example.com | `curl -s -o /dev/null -w "%{http_code}" https://example.com` | 403 (proxy denies) |
| google.com | `curl -s -o /dev/null -w "%{http_code}" https://google.com` | 403 (proxy denies) |

### 4. Direct Network - Blocked (bypass proxy)

| Test | Command | Expected |
|------|---------|----------|
| Direct HTTPS | `curl --max-time 5 --noproxy '*' https://example.com` | Timeout (nftables drops) |
| Direct HTTP | `curl --max-time 5 --noproxy '*' http://example.com` | Timeout (nftables drops) |

### 5. Secrets Availability

| Test | Command | Expected |
|------|---------|----------|
| Anthropic key exists | `test -r /run/secrets/anthropic_api_key` | Exit 0 |
| GitHub token exists | `test -r /run/secrets/github_token` | Exit 0 |
| HA token exists | `test -r /run/secrets/ha_access_token` | Exit 0 |

### 6. GitHub Issues Access

| Test | Command | Expected |
|------|---------|----------|
| List issues | `gh issue list --repo rhoerbe/EU23_admin` | Exit 0, lists issues |
| View issue | `gh issue view 10 --repo rhoerbe/EU23_admin` | Exit 0, shows issue content |

### 7. Playwright - HA Web UI

| Test | Action | Expected |
|------|--------|----------|
| HA landing page | Navigate to `http://10.4.4.10:8123` | Page loads, login form visible |
| Screenshot | Take screenshot of landing page | Screenshot saved |

## Test Structure

```
agent_containers/tests/
├── run_integration.sh      # Host: start container, run tests, cleanup
├── run_tests.sh            # Container: main test runner
├── test_ssh.sh             # SSH connectivity tests
├── test_proxy_allowed.sh   # Proxy allow tests
├── test_proxy_blocked.sh   # Proxy deny tests
├── test_network_blocked.sh # Direct network block tests
├── test_secrets.sh         # Secrets availability tests
├── test_github.sh          # GitHub CLI access tests
└── test_playwright.sh      # Playwright HA web UI tests
```

## Execution

### From host (as admin user)
```bash
cd agent_containers/tests
./run_integration.sh
```

### Test container startup
```bash
# Start test container (non-interactive)
podman --cgroup-manager=cgroupfs run --rm \
  --userns=keep-id \
  -v ~/.ssh:/home/$USER/.ssh:ro,Z \
  -v ./tests:/tests:ro,Z \
  --secret anthropic_api_key \
  --secret github_token \
  --secret ha_access_token \
  --network=ha-agent-net \
  -e HTTP_PROXY=http://host.containers.internal:8888 \
  -e HTTPS_PROXY=http://host.containers.internal:8888 \
  claude-ha-agent \
  /tests/run_tests.sh
```

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed
- `2` - Test environment error (missing secrets, network not configured)

## Prerequisites

Before running tests:
1. `ha_agent` user configured with secrets
2. Podman network `ha-agent-net` exists
3. tinyproxy running on host
4. nftables rules loaded
5. HA host (10.4.4.10) reachable and configured to accept agent SSH

## Test Output

```
[PASS] SSH to HA: connected successfully
[FAIL] SSH to 10.4.4.17: expected timeout, got connection refused
[PASS] Proxy allows github.com
[PASS] Proxy blocks example.com
...
Results: 12/14 passed, 2 failed
```
