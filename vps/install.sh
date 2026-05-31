#!/usr/bin/env bash
# install.sh — Set up Jarvis VPS backend on a fresh Linux server.
# Run as root or with sudo.  Idempotent.
set -euo pipefail

INSTALL_DIR="/root/jarvis/vps"
VENV_DIR="$INSTALL_DIR/.venv"
SERVICE_FILE="/etc/systemd/system/jarvis-vps.service"

echo "[1/5] Creating Python venv..."
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip -q
"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt" -q

echo "[2/5] Writing .env if missing..."
if [ ! -f "$INSTALL_DIR/../.env" ]; then
  cp "$INSTALL_DIR/../.env.template" "$INSTALL_DIR/../.env"
  echo "  → Created .env from template. Edit it before starting."
fi

echo "[3/5] Installing systemd service..."
cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=Jarvis VPS Brain
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/jarvis
ExecStart=/root/jarvis/vps/.venv/bin/uvicorn vps.main:app --host 0.0.0.0 --port 8765
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

echo "[4/5] Enabling and starting service..."
systemctl daemon-reload
systemctl enable jarvis-vps.service
systemctl restart jarvis-vps.service

echo "[5/5] Done."
echo "  Service status: systemctl status jarvis-vps"
echo "  Logs:           journalctl -u jarvis-vps -f"
echo "  Health check:   curl http://localhost:8765/health"
