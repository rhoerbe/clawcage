#!/bin/bash
# Entrypoint script for claude-ha-agent container
# Native Claude Code auto-updates in the background

set -e

# Execute the command passed to the container
exec "$@"
