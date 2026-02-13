#!/bin/bash
# Start claude-ha-agent container with least-privilege configuration
# Run as: ha_agent user
# Uses rootless Podman with --userns=keep-id for UID mapping
set -e

cd "$(dirname "$0")"

export XDG_RUNTIME_DIR=/run/user/$(id -u)

# Create directories if they don't exist
mkdir -p workspace sessions

# Remove old container if exists
podman --cgroup-manager=cgroupfs rm -f claude-ha-agent 2>/dev/null || true

podman --cgroup-manager=cgroupfs run -it --name claude-ha-agent \
  --userns=keep-id \
  -v ~/.ssh/id_ed25519:/home/$USER/.ssh/id_ed25519:ro,Z \
  -v ~/.ssh/id_ed25519-cert.pub:/home/$USER/.ssh/id_ed25519-cert.pub:ro,Z \
  -v ~/.ssh/config:/home/$USER/.ssh/config:ro,Z \
  -v ~/.claude/claude_code_config.json:/home/$USER/.claude/claude_code_config.json:ro,Z \
  -v ./workspace:/workspace:Z \
  -v ./sessions:/sessions:Z \
  --secret anthropic_api_key,target=/run/secrets/anthropic_api_key \
  --secret github_token,target=/run/secrets/github_token \
  --secret ha_access_token,target=/run/secrets/ha_access_token \
  --network=ha-agent-net \
  -e HTTP_PROXY=http://host.containers.internal:8888 \
  -e HTTPS_PROXY=http://host.containers.internal:8888 \
  claude-ha-agent \
  script -f ./sessions/session-$(date +%Y%m%d-%H%M%S).log -c claude-code
