#!/bin/sh
set -e

CONFIG_DIR="/home/crystalclaw/.crystalclaw"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Fix ownership of the mounted volume (may be root-owned from Docker)
mkdir -p "$CONFIG_DIR/workspace"
chown -R crystalclaw:crystalclaw "$CONFIG_DIR"

# Create default config and workspace if missing (as crystalclaw user)
if [ ! -f "$CONFIG_FILE" ]; then
    echo "🕷️ No config found — running onboard to create defaults..."
    su-exec crystalclaw /app/bin/crystalclaw onboard
fi

# Drop to crystalclaw user and exec the main command
exec su-exec crystalclaw /app/bin/crystalclaw "$@"
