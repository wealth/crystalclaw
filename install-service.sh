#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# install-service.sh — Install crystalclaw as a systemd service
#
# Usage:
#   sudo ./install-service.sh [OPTIONS]
#
# Options:
#   --no-build        Skip building the binary (use existing bin/crystalclaw)
#   --user USER       Run the service as USER (default: crystalclaw)
#   --install-dir DIR Install binary to DIR (default: /opt/crystalclaw)
#   --uninstall       Remove the service and installed files
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ──
SERVICE_NAME="crystalclaw"
SERVICE_USER="crystalclaw"
INSTALL_DIR="/opt/crystalclaw"
SKIP_BUILD=false
UNINSTALL=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse args ──
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)    SKIP_BUILD=true; shift ;;
        --user)        SERVICE_USER="$2"; shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --uninstall)   UNINSTALL=true; shift ;;
        -h|--help)
            head -n 12 "$0" | tail -n +3 | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Must be root ──
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root (use sudo)."
    exit 1
fi

# ── Uninstall path ──
if $UNINSTALL; then
    echo "🗑️  Uninstalling ${SERVICE_NAME}..."
    systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    echo "   Removed service unit."
    echo "   Binary and data at ${INSTALL_DIR} were NOT removed (do so manually if desired)."
    echo "   User '${SERVICE_USER}' was NOT removed."
    echo "✅ Uninstall complete."
    exit 0
fi

echo "🕷️  Installing ${SERVICE_NAME} as a systemd service..."

# ── 1. Build the binary ──
if ! $SKIP_BUILD; then
    echo "📦 Building release binary..."
    if ! command -v shards &>/dev/null; then
        echo "❌ 'shards' not found. Install Crystal first: https://crystal-lang.org/install"
        exit 1
    fi
    (cd "$SCRIPT_DIR" && shards build --release --no-debug)
    echo "   Build complete."
else
    if [[ ! -f "${SCRIPT_DIR}/bin/crystalclaw" ]]; then
        echo "❌ No binary found at ${SCRIPT_DIR}/bin/crystalclaw — build first or remove --no-build."
        exit 1
    fi
    echo "⏭️  Skipping build (--no-build)."
fi

# ── 2. Create system user ──
if ! id "${SERVICE_USER}" &>/dev/null; then
    echo "👤 Creating system user '${SERVICE_USER}'..."
    useradd --system --shell /usr/sbin/nologin --home-dir "/home/${SERVICE_USER}" --create-home "${SERVICE_USER}"
else
    echo "👤 User '${SERVICE_USER}' already exists."
fi

# ── 3. Install binary and workspace files ──
echo "📂 Installing to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}/bin"
cp "${SCRIPT_DIR}/bin/crystalclaw" "${INSTALL_DIR}/bin/crystalclaw"
chmod 755 "${INSTALL_DIR}/bin/crystalclaw"

# Copy workspace templates if they exist
if [[ -d "${SCRIPT_DIR}/workspace" ]]; then
    cp -r "${SCRIPT_DIR}/workspace" "${INSTALL_DIR}/workspace"
fi

chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"

# Ensure the user home config dir exists
CONFIG_DIR="/home/${SERVICE_USER}/.crystalclaw"
mkdir -p "${CONFIG_DIR}"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${CONFIG_DIR}"

# ── 4. Create environment file ──
ENV_FILE="/etc/crystalclaw.env"
if [[ ! -f "${ENV_FILE}" ]]; then
    echo "📝 Creating environment file at ${ENV_FILE}..."
    cat > "${ENV_FILE}" <<'EOF'
# CrystalClaw environment configuration
# Edit this file to configure the service, then run:
#   sudo systemctl restart crystalclaw

# PostgreSQL connection URL (required for PG-backed storage)
# CRYSTALCLAW_POSTGRES_URL=postgres://crystalclaw:crystalclaw@localhost:5432/crystalclaw
EOF
    chmod 600 "${ENV_FILE}"
    echo "   ⚠️  Edit ${ENV_FILE} to configure your environment variables."
else
    echo "📝 Environment file ${ENV_FILE} already exists — not overwriting."
fi

# ── 5. Install systemd unit ──
echo "⚙️  Installing systemd service unit..."
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=CrystalClaw AI Assistant Gateway
Documentation=https://github.com/crystalclaw/crystalclaw
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/bin/crystalclaw gateway
EnvironmentFile=${ENV_FILE}
Restart=on-failure
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=60

# Hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/${SERVICE_USER}/.crystalclaw
PrivateTmp=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

echo ""
echo "✅ Installation complete!"
echo ""
echo "   Binary:      ${INSTALL_DIR}/bin/crystalclaw"
echo "   Config dir:  ${CONFIG_DIR}"
echo "   Env file:    ${ENV_FILE}"
echo "   Service:     ${SERVICE_NAME}.service"
echo ""
echo "Next steps:"
echo "  1. Edit ${ENV_FILE} to set CRYSTALCLAW_POSTGRES_URL and any other env vars"
echo "  2. Start the service:"
echo "       sudo systemctl start ${SERVICE_NAME}"
echo "  3. Check status / logs:"
echo "       sudo systemctl status ${SERVICE_NAME}"
echo "       sudo journalctl -u ${SERVICE_NAME} -f"
