#!/bin/bash
set -e

echo "======================================"
echo " Ubuntu XFCE Firefox + Tailscale"
echo "======================================"

echo "[1/3] Starting Tailscale..."

tailscaled >/tmp/tailscaled.log 2>&1 &

sleep 3

if [ -z "$TS_AUTHKEY" ]; then
    echo "ERROR: TS_AUTHKEY is not configured."
    exit 1
fi

echo "[2/3] Connecting to Tailscale..."

tailscale up \
    --auth-key="$TS_AUTHKEY" \
    --hostname="ubuntu-firefox"

echo "[3/3] Tailscale connected!"

echo
echo "Tailscale IP:"
tailscale ip -4

echo
tailscale status

# IMPORTANT:
# The original XFCE/noVNC startup process must continue here.
