#!/bin/bash
# Entrypoint script for claude-ha-agent container
# Updates Claude Code to latest version on every container start

set -e

echo "Checking for Claude Code updates..."
npm install -g @anthropic-ai/claude-code@latest --cache /workspace/.npm 2>&1 | grep -v "^npm WARN" || true
echo "Claude Code ready."

# Execute the command passed to the container
exec "$@"
