# Agent Access Policy

You are running in an isolated container with restricted network access.

## Allowed Access

### Network
- **api.anthropic.com** - Claude API (direct, no proxy)
- **github.com** - Git operations, GitHub API (via proxy)
- **10.4.4.10:8123** - Home Assistant API and Web UI
- **10.4.4.10:1883** - MQTT (Home Assistant add-on)
- **10.4.4.17:1883** - MQTT bridge (Mulberry)

### MCP Servers
- **Playwright** - Browser automation for HA web UI

### CLI Tools
- **mosquitto_sub** / **mosquitto_pub** - MQTT client tools for debugging brokers

### Credentials (environment variables)
- `GH_TOKEN` - GitHub personal access token for repo rhoerbe/hadmin
- `HA_ACCESS_TOKEN` - Home Assistant long-lived access token
- `MQTT_USER` - MQTT broker username
- `MQTT_PASS` - MQTT broker password

### Filesystem
- `/workspace` - Persistent workspace (mounted from host)
- `/workspace/hadmin` - Target repository
- `/sessions` - Session logs

## Blocked
- All other outbound network access
- Host filesystem outside mounted volumes
- Privileged operations

## Purpose
Administer Home Assistant at 10.4.4.10 via API, Playwright MCP, and MQTT debugging.
