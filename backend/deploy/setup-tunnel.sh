#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Cloudflare Tunnel Setup for SafeNetic
# Run AFTER setup.sh and AFTER logging into Cloudflare
# ═══════════════════════════════════════════════════════════════

set -e

echo "═══════════════════════════════════════════════════"
echo "  Cloudflare Tunnel Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# Step 1: Authenticate with Cloudflare
echo "[1/4] Logging into Cloudflare..."
echo "A browser link will appear — copy it and open on your PC to authorize."
echo ""
cloudflared tunnel login

# Step 2: Create tunnel
echo ""
echo "[2/4] Creating tunnel 'safenetic-backend'..."
cloudflared tunnel create safenetic-backend

# Get tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep safenetic-backend | awk '{print $1}')
echo "Tunnel ID: $TUNNEL_ID"

# Step 3: Create config
echo ""
echo "[3/4] Creating tunnel config..."
mkdir -p /etc/cloudflared

cat > /etc/cloudflared/config.yml << EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/${TUNNEL_ID}.json

ingress:
  - hostname: alerts.safenetic.online
    service: http://127.0.0.1:8000
  - service: http_status:404
EOF

echo "Config written to /etc/cloudflared/config.yml"

# Step 4: Set up DNS route
echo ""
echo "[4/4] Creating DNS route..."
cloudflared tunnel route dns safenetic-backend alerts.safenetic.online

# Install cloudflared as a system service
echo ""
echo "Installing cloudflared as a system service..."
cloudflared service install
systemctl enable cloudflared
systemctl start cloudflared

echo ""
echo "═══════════════════════════════════════════════════"
echo "  ✅ Cloudflare Tunnel Active!"
echo "═══════════════════════════════════════════════════"
echo ""
echo "  https://alerts.safenetic.online → localhost:8000"
echo ""
echo "  Check status: systemctl status cloudflared"
echo "  View logs:    journalctl -u cloudflared -f"
echo ""
