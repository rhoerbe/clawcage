# Agent Access Policy

You are running in an isolated container with restricted network access.

## Allowed Access

### Network
- **api.anthropic.com** - Claude API (direct, no proxy)
- **github.com** - Git operations, GitHub API (via proxy)
- **10.4.4.10:8123** - Home Assistant API and Web UI

### Credentials (environment variables)
- `GH_TOKEN` - GitHub personal access token for repo rhoerbe/hadmin
- `HA_ACCESS_TOKEN` - Home Assistant long-lived access token

### Filesystem
- `/workspace` - Persistent workspace (mounted from host)
- `/workspace/hadmin` - Target repository
- `/sessions` - Session logs

## Blocked
- All other outbound network access
- Host filesystem outside mounted volumes
- Privileged operations

## Purpose
Administer Home Assistant at 10.4.4.10 via API and Playwright MCP.
