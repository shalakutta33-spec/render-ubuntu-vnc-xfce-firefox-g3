#!/bin/bash
set -e

echo "======================================"
echo " Ubuntu XFCE + Firefox + Tailscale"
echo "======================================"
echo "uid=$(id -u):$(id -g) home=$HOME"

# ponytail: rootless VNC+noVNC, no sudo (Render runs as 1001, Accetto startup needs root)
export HOME=${HOME:-/home/headless}
export DISPLAY=${DISPLAY:-:1}
export VNC_PORT=${VNC_PORT:-5901}
export VNC_COL_DEPTH=${VNC_COL_DEPTH:-24}
export VNC_RESOLUTION=${VNC_RESOLUTION:-1360x768}
export VNC_PW=${VNC_PW:-headless}
export VNC_CONFIG_HOME=${VNC_CONFIG_HOME:-$HOME/.config/tigervnc}
export NOVNC_HOME=${NOVNC_HOME:-/usr/libexec/noVNCdim}
export NOVNC_PORT=${PORT:-${NOVNC_PORT:-6901}}
export NOVNC_HEARTBEAT=${NOVNC_HEARTBEAT:-30}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-/data/.config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-/data/.cache}
echo "VNC $DISPLAY port=$VNC_PORT novnc=$NOVNC_PORT heartbeat=$NOVNC_HEARTBEAT"

if [ -z "$TS_AUTHKEY" ]; then
    echo "WARN: TS_AUTHKEY not set, skipping Tailscale."
else
    echo "[1/3] Starting Tailscale daemon..."
    rm -f /tmp/tailscaled.sock
    tailscaled --tun=userspace-networking --state=/tmp/tailscaled.state --socket=/tmp/tailscaled.sock >/tmp/tailscaled.log 2>&1 &
    TAILSCALED_PID=$!
    sleep 3
    cat /tmp/tailscaled.log || true
    if ! kill -0 "$TAILSCALED_PID" 2>/dev/null; then
        echo "WARN: tailscaled failed, continuing without Tailscale."
    else
        echo "[2/3] Connecting to Tailscale..."
        tailscale --socket=/tmp/tailscaled.sock up --auth-key="$TS_AUTHKEY" --hostname="ubuntu-firefox" --accept-dns=false || echo "WARN: tailscale up failed, continuing."
        tailscale --socket=/tmp/tailscaled.sock set --ssh || echo "WARN: tailscale ssh enable failed, continuing."
        echo "Tailscale IP:"; tailscale --socket=/tmp/tailscaled.sock ip -4 || true
    fi
fi

echo "Preparing writable dirs..."
mkdir -p "$VNC_CONFIG_HOME" /data/.config/tigervnc /data/.cache /tmp/.X11-unix "$HOME/.vnc" 2>/dev/null || true
chmod 777 /tmp /tmp/.X11-unix 2>/dev/null || true
rm -rf /tmp/.X*-lock /tmp/.X11-unix/* 2>/dev/null || true

echo "$VNC_PW" | vncpasswd -f > "$VNC_CONFIG_HOME/passwd"
chmod 600 "$VNC_CONFIG_HOME/passwd"
printf 'rfbport=%s\ndepth=%s\ngeometry=%s\nBlacklistTimeout=0\n' "$VNC_PORT" "$VNC_COL_DEPTH" "$VNC_RESOLUTION" > "$VNC_CONFIG_HOME/config"

echo "Starting VNC on $DISPLAY port $VNC_PORT..."
vncserver "$DISPLAY" > /tmp/vnc.log 2>&1 &
VNC_PID=$!
sleep 4
cat /tmp/vnc.log || true
if ! kill -0 "$VNC_PID" 2>/dev/null; then
    echo "ERROR: vncserver died, log above."
fi
pgrep -a Xvnc || true
(ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null || echo "no ss/netstat") | grep -E "5901|$VNC_PORT" || true

echo "Starting noVNC $NOVNC_PORT -> localhost:$VNC_PORT..."
"$NOVNC_HOME/utils/novnc_proxy" --vnc "localhost:${VNC_PORT}" --listen "${NOVNC_PORT}" ${NOVNC_HEARTBEAT:+--heartbeat "${NOVNC_HEARTBEAT}"} > /tmp/novnc.log 2>&1 &
NOVNC_PID=$!
sleep 3
cat /tmp/novnc.log || true
if ! kill -0 "$NOVNC_PID" 2>/dev/null; then
    echo "ERROR: novnc_proxy died, log above."
    exit 1
fi

touch /tmp/tailscaled.log 2>/dev/null || true
tail -F /tmp/vnc.log /tmp/novnc.log /tmp/tailscaled.log 2>/dev/null &
wait $NOVNC_PID
