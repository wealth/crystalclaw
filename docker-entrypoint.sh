#!/bin/sh
set -e

CONFIG_DIR="${HOME}/.crystalclaw"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Create default config and workspace if missing
if [ ! -f "$CONFIG_FILE" ]; then
    echo "🕷️ No config found — running onboard to create defaults..."
    /app/bin/crystalclaw onboard
fi

exec /app/bin/crystalclaw "$@"
