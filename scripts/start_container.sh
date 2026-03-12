#!/bin/bash
# Start claude-ha-agent container with least-privilege configuration
# Uses rootless Podman with --userns=keep-id for UID mapping
#
# Usage:
#   start-ha-agent              # start Claude Code with TUI
#   start-ha-agent --quick      # start Claude Code without TUI (use defaults)
#   start-ha-agent --test       # run preflight and network connectivity tests
#   start-ha-agent bash         # start bash shell
set -e

AGENT_USER="ha_agent"
AGENT_HOME="/home/$AGENT_USER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Re-exec as ha_agent if not already
if [[ "$(id -un)" != "$AGENT_USER" ]]; then
    exec sudo -iu "$AGENT_USER" "$AGENT_HOME/start_container.sh" "$@"
fi

# Determine paths based on environment (development repo vs deployed agent home)
if [[ -d "$SCRIPT_DIR/../containerize" ]]; then
    # Development: running from repo's scripts/ directory
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    TEST_CONTAINER_SH="$REPO_ROOT/containerize/test_container.sh"
    MCP_CONFIG_SRC="$REPO_ROOT/mcp-config.json"
else
    # Production: deployed to agent's home directory
    TEST_CONTAINER_SH="$SCRIPT_DIR/test_container.sh"
    MCP_CONFIG_SRC="$SCRIPT_DIR/mcp-config.json"
fi

# Load configuration
source "$SCRIPT_DIR/config.sh"

CONTAINER_NAME="$CONTAINER_IMAGE"

# TUI state variables
SELECTED_PERMISSION_MODE="$DEFAULT_PERMISSION_MODE"
SELECTED_MCP_SERVERS=("${DEFAULT_MCP_SERVERS[@]}")
SELECTED_SESSION=""
SKIP_TUI=false

# Parse initial arguments
for arg in "$@"; do
    case "$arg" in
        --quick)
            SKIP_TUI=true
            shift
            ;;
    esac
done

# ============================================================================
# TUI Functions
# ============================================================================

export_config_for_tui() {
    # Export configuration as environment variables for Python TUI
    export AGENT_HOME
    export REPO_NAME
    export CONTAINER_IMAGE

    # Permission modes as comma-separated
    export PERMISSION_MODES="${PERMISSION_MODES[*]}"
    PERMISSION_MODES="${PERMISSION_MODES// /,}"
    export DEFAULT_PERMISSION_MODE

    # MCP servers as pipe-separated (since entries contain colons)
    local mcp_str=""
    for server in "${AVAILABLE_MCP_SERVERS[@]}"; do
        [[ -n "$mcp_str" ]] && mcp_str+="|"
        mcp_str+="$server"
    done
    export AVAILABLE_MCP_SERVERS="$mcp_str"
    export DEFAULT_MCP_SERVERS="${DEFAULT_MCP_SERVERS[*]}"
    DEFAULT_MCP_SERVERS="${DEFAULT_MCP_SERVERS// /,}"

    # Secrets as pipe-separated
    local secrets_str=""
    for secret in "${REQUIRED_SECRETS[@]}"; do
        [[ -n "$secrets_str" ]] && secrets_str+="|"
        secrets_str+="$secret"
    done
    export REQUIRED_SECRETS="$secrets_str"

    secrets_str=""
    for secret in "${OPTIONAL_SECRETS[@]}"; do
        [[ -n "$secrets_str" ]] && secrets_str+="|"
        secrets_str+="$secret"
    done
    export OPTIONAL_SECRETS="$secrets_str"
}

run_python_tui() {
    export_config_for_tui

    local tui_script="$SCRIPT_DIR/launcher_tui.py"
    if [[ ! -f "$tui_script" ]]; then
        echo "Error: TUI script not found: $tui_script" >&2
        return 1
    fi

    # Use venv python if available
    local py="python3"
    if [[ -x "$AGENT_HOME/.venv/bin/python" ]]; then
        py="$AGENT_HOME/.venv/bin/python"
    fi

    # Run TUI - JSON output is written to a temp file
    local tui_output_file="/tmp/launcher_tui_result.json"
    rm -f "$tui_output_file"
    export TUI_OUTPUT_FILE="$tui_output_file"

    if ! $py "$tui_script"; then
        return 1
    fi

    if [[ ! -f "$tui_output_file" ]]; then
        return 1
    fi

    local tui_output
    tui_output=$(cat "$tui_output_file")
    rm -f "$tui_output_file"

    if [[ -z "$tui_output" ]]; then
        return 1
    fi

    # Parse JSON output using python
    local action permission_mode mcp_servers session_arg
    action=$(echo "$tui_output" | $py -c "import sys, json; d=json.load(sys.stdin); print(d.get('action', ''))")

    if [[ "$action" != "start" ]]; then
        return 1
    fi

    permission_mode=$(echo "$tui_output" | $py -c "import sys, json; d=json.load(sys.stdin); print(d.get('permission_mode', ''))")
    mcp_servers=$(echo "$tui_output" | $py -c "import sys, json; d=json.load(sys.stdin); print(','.join(d.get('mcp_servers', [])))")
    session_arg=$(echo "$tui_output" | $py -c "import sys, json; d=json.load(sys.stdin); print(d.get('session_arg', ''))")

    # Apply selections
    SELECTED_PERMISSION_MODE="$permission_mode"
    IFS=',' read -ra SELECTED_MCP_SERVERS <<< "$mcp_servers"
    SELECTED_SESSION="$session_arg"

    return 0
}

build_mcp_config() {
    local config_file="$AGENT_HOME/workspace/$REPO_NAME/.claude/settings.json"
    local temp_file="${config_file}.tmp"

    # Start building JSON
    echo '{' > "$temp_file"
    echo '  "mcpServers": {' >> "$temp_file"

    local first=true
    for server_name in "${SELECTED_MCP_SERVERS[@]}"; do
        # Find the package for this server
        for server in "${AVAILABLE_MCP_SERVERS[@]}"; do
            local name package description
            IFS=':' read -r name package description <<< "$server"
            if [[ "$name" == "$server_name" ]]; then
                if [[ "$first" == true ]]; then
                    first=false
                else
                    echo ',' >> "$temp_file"
                fi
                cat >> "$temp_file" << EOF
    "$name": {
      "command": "npx",
      "args": ["$package"]
    }
EOF
                break
            fi
        done
    done

    echo '' >> "$temp_file"
    echo '  }' >> "$temp_file"
    echo '}' >> "$temp_file"

    mv "$temp_file" "$config_file"
}

build_claude_args() {
    local args="--permission-mode $SELECTED_PERMISSION_MODE"

    if [[ -n "$SELECTED_SESSION" ]]; then
        args="$args $SELECTED_SESSION"
    fi

    echo "$args"
}

show_final_command() {
    local claude_args
    claude_args=$(build_claude_args)

    echo ""
    echo "Starting container with command:"
    echo "  claude $claude_args"
    echo ""
    echo "MCP Servers enabled: ${SELECTED_MCP_SERVERS[*]:-none}"
    echo ""
}

run_tui() {
    if ! run_python_tui; then
        echo "Cancelled."
        exit 0
    fi
    return 0
}

# ============================================================================
# Main Script
# ============================================================================

export XDG_RUNTIME_DIR=/run/user/$(id -u)

# Create directories if they don't exist
mkdir -p "$AGENT_HOME/workspace/$REPO_NAME/.claude/projects" "$AGENT_HOME/sessions"

# Handle --test flag
if [[ "$1" == "--test" ]]; then
    exec "$TEST_CONTAINER_SH" all
fi

# Run preflight checks (exit on failure)
"$TEST_CONTAINER_SH" preflight || exit 1

# Load tokens for CLI tools
GH_TOKEN=$(cat "$AGENT_HOME/workspace/.secrets/github_token")
# ANTHROPIC_API_KEY=$(cat "$AGENT_HOME/workspace/.secrets/anthropic_api_key")  # using OAuth token instead
HA_ACCESS_TOKEN=$(cat "$AGENT_HOME/workspace/.secrets/ha_access_token")

# MQTT credentials (optional - create files if MQTT debugging is needed)
MQTT_USER=""
MQTT_PASS=""
if [[ -f "$AGENT_HOME/workspace/.secrets/mqtt_username" ]]; then
    MQTT_USER=$(cat "$AGENT_HOME/workspace/.secrets/mqtt_username")
fi
if [[ -f "$AGENT_HOME/workspace/.secrets/mqtt_password" ]]; then
    MQTT_PASS=$(cat "$AGENT_HOME/workspace/.secrets/mqtt_password")
fi

# Handle direct command execution (e.g., "start-ha-agent bash")
if [[ $# -gt 0 && "$1" != "--"* ]]; then
    # Remove old container if exists
    podman --cgroup-manager=cgroupfs rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # Start container with the provided command
    exec podman --cgroup-manager=cgroupfs run --rm -it \
        --name "$CONTAINER_NAME" \
        --userns=keep-id \
        -v "$AGENT_HOME/workspace":/workspace:Z \
        -v "$AGENT_HOME/sessions":/sessions:Z \
        -w "/workspace/$REPO_NAME" \
        --network=ha-agent-net \
        -e HTTP_PROXY=http://host.containers.internal:8888 \
        -e HTTPS_PROXY=http://host.containers.internal:8888 \
        -e NO_PROXY="api.anthropic.com,claude.ai,platform.claude.com,anthropic.com" \
        -e HOME=/workspace \
        -e GH_TOKEN="$GH_TOKEN" \
        -e HA_ACCESS_TOKEN="$HA_ACCESS_TOKEN" \
        -e MQTT_USER="$MQTT_USER" \
        -e MQTT_PASS="$MQTT_PASS" \
        "$CONTAINER_NAME" \
        "$@"
fi

# Run TUI if not skipped
if [[ "$SKIP_TUI" == false ]]; then
    # Check if Python TUI dependencies are available (prefer venv)
    PYTHON_CMD="python3"
    if [[ -x "$AGENT_HOME/.venv/bin/python" ]]; then
        PYTHON_CMD="$AGENT_HOME/.venv/bin/python"
    fi
    if ! $PYTHON_CMD -c "import textual" &> /dev/null; then
        echo "Warning: textual not installed, using default settings"
        echo "Install with: python3 -m venv ~/.venv && ~/.venv/bin/pip install textual"
        SKIP_TUI=true
    else
        run_tui
    fi
fi

# Build MCP config from selections
build_mcp_config

# Build final Claude arguments
CLAUDE_ARGS=$(build_claude_args)

# Show final command
show_final_command

# Remove old container if exists
podman --cgroup-manager=cgroupfs rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Start container with Claude
exec podman --cgroup-manager=cgroupfs run --rm -it \
    --name "$CONTAINER_NAME" \
    --userns=keep-id \
    -v "$AGENT_HOME/workspace":/workspace:Z \
    -v "$AGENT_HOME/sessions":/sessions:Z \
    -w "/workspace/$REPO_NAME" \
    --network=ha-agent-net \
    -e HTTP_PROXY=http://host.containers.internal:8888 \
    -e HTTPS_PROXY=http://host.containers.internal:8888 \
    -e NO_PROXY="api.anthropic.com,claude.ai,platform.claude.com,anthropic.com" \
    -e HOME=/workspace \
    -e GH_TOKEN="$GH_TOKEN" \
    -e HA_ACCESS_TOKEN="$HA_ACCESS_TOKEN" \
    -e MQTT_USER="$MQTT_USER" \
    -e MQTT_PASS="$MQTT_PASS" \
    "$CONTAINER_NAME" \
    claude $CLAUDE_ARGS