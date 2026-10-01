#!/bin/bash
set -e

echo "======================================"
echo " Ubuntu XFCE + Firefox + Tailscale"
echo "======================================"

if [ -z "$TS_AUTHKEY" ]; then
    echo "ERROR: TS_AUTHKEY is not set."
    exit 1
fi

echo "[1/3] Starting Tailscale daemon..."

tailscaled >/tmp/tailscaled.log 2>&1 &

sleep 3

echo "[2/3] Connecting to Tailscale..."

tailscale up \
    --auth-key="$TS_AUTHKEY" \
    --hostname="ubuntu-firefox"

echo
echo "[3/3] Tailscale connected!"
echo
echo "Tailscale IP:"
tailscale ip -4
echo

echo "Starting Accetto..."
exec /usr/bin/tini -- /dockerstartup/startup.sh
