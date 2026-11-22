#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# SafeNetic Backend — Oracle Cloud VM Setup Script
# Run this ONCE after SSH-ing into your new Oracle Cloud VM
# Usage: chmod +x setup.sh && sudo ./setup.sh
# ═══════════════════════════════════════════════════════════════

set -e

echo "═══════════════════════════════════════════════════"
echo "  SafeNetic Backend — Oracle Cloud Setup"
echo "═══════════════════════════════════════════════════"

# --- 1. System Updates ---
echo ""
echo "[1/6] Updating system packages..."
apt update && apt upgrade -y

# --- 2. Install Python 3.11+ and pip ---
echo ""
echo "[2/6] Installing Python..."
apt install -y python3 python3-pip python3-venv

# --- 3. Create app user and directory ---
echo ""
echo "[3/6] Setting up app directory..."
APP_DIR="/opt/safenetic"
mkdir -p $APP_DIR
# If running as root, create a dedicated user
if ! id "safenetic" &>/dev/null; then
    useradd --system --no-create-home --shell /bin/false safenetic
fi
install -d -o root -g safenetic -m 0750 /etc/safenetic

# --- 4. Set up Python virtual environment ---
echo ""
echo "[4/6] Creating Python virtual environment..."
python3 -m venv $APP_DIR/venv
source $APP_DIR/venv/bin/activate
pip install --upgrade pip
pip install -r $APP_DIR/requirements.txt
deactivate

# --- 5. Install cloudflared ---
echo ""
echo "[5/6] Installing Cloudflare Tunnel (cloudflared)..."
if ! command -v cloudflared &>/dev/null; then
    curl -L --output /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb
    rm /tmp/cloudflared.deb
fi
echo "cloudflared version: $(cloudflared --version)"

# --- 6. Install systemd service ---
echo ""
echo "[6/6] Installing systemd service..."
cp $APP_DIR/deploy/safenetic.service /etc/systemd/system/safenetic.service
systemctl daemon-reload
systemctl enable safenetic
echo "Systemd service installed and enabled."

# --- Set permissions ---
chown -R safenetic:safenetic $APP_DIR

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ Setup Complete!"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Configure Firebase credentials outside the app folder:"
echo "     /etc/safenetic/firebase-service-account.json"
echo "     owner root:safenetic, permissions 0640"
echo "  2. Never put the credential in the source tree or Git."
echo "  3. Set up Cloudflare Tunnel (see guide)"
echo "  4. Start the service: sudo systemctl start safenetic"
echo "  5. Check status: sudo systemctl status safenetic"
echo "  6. View logs: sudo journalctl -u safenetic -f"
echo ""
