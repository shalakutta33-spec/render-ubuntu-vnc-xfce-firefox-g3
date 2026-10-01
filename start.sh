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

rm -f /tmp/tailscaled.sock
# ponytail: userspace networking, no NET_ADMIN/TUN needed on Deplexo
tailscaled --tun=userspace-networking --state=/tmp/tailscaled.state --socket=/tmp/tailscaled.sock >/tmp/tailscaled.log 2>&1 &
TAILSCALED_PID=$!

sleep 3
cat /tmp/tailscaled.log || true

if ! kill -0 "$TAILSCALED_PID" 2>/dev/null; then
    echo "ERROR: tailscaled failed to start (see log above)."
    exit 1
fi

echo "[2/3] Connecting to Tailscale..."

tailscale --socket=/tmp/tailscaled.sock up \
    --auth-key="$TS_AUTHKEY" \
    --hostname="ubuntu-firefox" \
    --accept-dns=false

echo
echo "[3/3] Tailscale connected!"
echo
echo "Tailscale IP:"
tailscale --socket=/tmp/tailscaled.sock ip -4
echo

echo "Preparing writable dirs (/data, /tmp)..."
mkdir -p /data/.config/tigervnc /data/.cache/Tailscale /tmp
export XDG_CONFIG_HOME=/data/.config XDG_CACHE_HOME=/data/.cache VNC_CONFIG_HOME=/data/.config/tigervnc
# best-effort: keep symlinks if base image layout changed (rootfs may be RO, ignore errors)
if [ ! -L /home/headless/.config ]; then rm -rf /home/headless/.config 2>/dev/null; ln -s /data/.config /home/headless/.config 2>/dev/null || true; fi
if [ ! -L /home/headless/.cache ]; then rm -rf /home/headless/.cache 2>/dev/null; ln -s /data/.cache /home/headless/.cache 2>/dev/null || true; fi

echo "Starting Accetto..."
exec /usr/bin/tini -- /dockerstartup/startup.sh
