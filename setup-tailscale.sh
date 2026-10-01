```bash
#!/bin/bash

set -e

echo "=========================================="
echo "   Tailscale Setup"
echo "=========================================="
echo

# ------------------------------------------
# 1. Check auth key
# ------------------------------------------

if [ -z "${TS_AUTHKEY:-}" ]; then
    echo "ERROR: TS_AUTHKEY is not set."
    echo
    echo "Make sure Deplexo has this environment variable:"
    echo
    echo "TS_AUTHKEY=tskey-xxxxxxxxxxxxxxxx"
    echo
    exit 1
fi

echo "[1/5] TS_AUTHKEY detected."
echo

# ------------------------------------------
# 2. Install Tailscale
# ------------------------------------------

if command -v tailscale >/dev/null 2>&1; then
    echo "[2/5] Tailscale is already installed."
else
    echo "[2/5] Installing Tailscale..."

    apt-get update
    apt-get install -y curl

    curl -fsSL https://tailscale.com/install.sh | sh

    rm -rf /var/lib/apt/lists/*

    echo "Tailscale installed."
fi

echo

# ------------------------------------------
# 3. Start Tailscale daemon
# ------------------------------------------

echo "[3/5] Starting Tailscale daemon..."

if pgrep -x tailscaled >/dev/null 2>&1; then
    echo "tailscaled is already running."
else
    tailscaled >/tmp/tailscaled.log 2>&1 &
    sleep 3
fi

echo

# ------------------------------------------
# 4. Connect to Tailnet
# ------------------------------------------

echo "[4/5] Connecting to Tailscale..."

tailscale up \
    --auth-key="$TS_AUTHKEY" \
    --hostname="ubuntu-firefox"

echo

# ------------------------------------------
# 5. Show connection information
# ------------------------------------------

echo "[5/5] Tailscale connection:"
echo

tailscale status

echo
echo "=========================================="
echo "   Tailscale is connected! ✅"
echo "=========================================="
echo

echo "Tailscale IPv4:"
tailscale ip -4

echo

echo "VNC address:"
echo "$(tailscale ip -4):5901"

echo
echo "Setup complete. 🎉"
```
