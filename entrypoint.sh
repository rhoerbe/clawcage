#!/bin/bash
# Entrypoint script for claude-ha-agent container
# - Update Claude Code to latest version on every container start

set -e

# Update Claude Code to latest version (only if we have permissions)
if [[ -w /usr/local/lib/node_modules ]]; then
    echo "Checking for Claude Code updates..."
    npm install -g @anthropic-ai/claude-code@latest --cache /workspace/.npm 2>&1 | grep -v "^npm WARN" || true
    echo "Claude Code ready."
else
    echo "Note: Cannot update Claude Code (insufficient permissions). Running installed version."
fi

# Execute the command passed to the container
exec "$@"
