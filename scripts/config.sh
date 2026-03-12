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

# MCP servers are defined in containerize/mcp-manifest.json
# Default enabled MCP servers (must be listed in manifest as "installed")
DEFAULT_MCP_SERVERS=("playwright")

# Required secrets (name:description)
REQUIRED_SECRETS=(
    "github_token:GitHub personal access token"
    "ha_access_token:Home Assistant access token"
)

# Optional secrets
OPTIONAL_SECRETS=(
    "anthropic_api_key:Anthropic API key (alternative to OAuth)"
    "mqtt_username:MQTT broker username"
    "mqtt_password:MQTT broker password"
)
