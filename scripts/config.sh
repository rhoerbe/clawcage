# Container configuration
REPO_NAME="hadmin"
CONTAINER_IMAGE="claude-ha-agent"

# Default Claude arguments
DEFAULT_PERMISSION_MODE="bypassPermissions"
CLAUDE_ARGS="--permission-mode $DEFAULT_PERMISSION_MODE"

# Available permission modes for TUI selection
PERMISSION_MODES=(
    "default"
    "acceptEdits"
    "bypassPermissions"
    "plan"
    "dontAsk"
)

# MCP servers are defined in containerize/mcp-manifest.json (or /etc/freigang/mcp-manifest.json in container)
# Default enabled MCP servers (must be listed in manifest as "installed")
# NOTE: All MCP servers are OFF by default on first start. Filesystem access is always on via Claude Code itself.
# User preferences are persisted in $AGENT_HOME/workspace/$REPO_NAME/.claude/launcher_preferences.json
DEFAULT_MCP_SERVERS=()

# Selectable secrets - shown in TUI for user selection
SELECTABLE_SECRETS=(
    "github_token:GitHub token"
    "ha_access_token:HA token"
    "mqtt_username:MQTT user"
    "mqtt_password:MQTT pass"
)
