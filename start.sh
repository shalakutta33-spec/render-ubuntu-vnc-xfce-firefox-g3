#!/bin/bash

set -e

CONTAINER="ubuntu-firefox"

echo "======================================"
echo " Ubuntu XFCE Firefox + Tailscale"
echo "======================================"
echo

echo "[1/6] Building and starting container..."
docker compose up -d --build

echo
echo "[2/6] Waiting for container..."

until docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true; do
    sleep 1
done

echo "Container is running."

echo
echo "[3/6] Starting Tailscale daemon..."

if ! docker exec "$CONTAINER" pgrep tailscaled >/dev/null 2>&1; then
    docker exec "$CONTAINER" bash -c 'tailscaled >/tmp/tailscaled.log 2>&1 &'
    sleep 3
else
    echo "Tailscale daemon is already running."
fi

echo
echo "[4/6] Checking Tailscale..."

sleep 2

STATUS=$(docker exec "$CONTAINER" tailscale status 2>&1 || true)

if echo "$STATUS" | grep -q "Logged out"; then

    echo
    echo "Tailscale is not logged in."
    echo
    echo "Enter your Tailscale auth key."
    echo

    read -rsp "Enter Tailscale auth key: " TS_KEY
    echo

    if [ -z "$TS_KEY" ]; then
        echo
        echo "Error: No Tailscale auth key entered."
        exit 1
    fi

    echo
    echo "Logging in to Tailscale..."

    printf '%s\n' "$TS_KEY" | \
        docker exec -i "$CONTAINER" bash -c '
            IFS= read -r TS_KEY
            tailscale up --auth-key="$TS_KEY"
            unset TS_KEY
        '

    unset TS_KEY

elif echo "$STATUS" | grep -q "Tailscale is stopped"; then

    echo
    echo "Tailscale daemon is not ready."
    echo
    echo "Tailscale log:"
    docker exec "$CONTAINER" tail -30 /tmp/tailscaled.log 2>/dev/null || true
    echo
    echo "Try running:"
    echo "docker exec $CONTAINER tailscaled"
    exit 1

else

    echo "Tailscale is already authenticated."

fi

echo
echo "[5/6] Checking Tailscale connection..."

sleep 2

docker exec "$CONTAINER" tailscale status

echo
echo "[6/6] Tailscale IP:"

TAILSCALE_IP=$(docker exec "$CONTAINER" tailscale ip -4)

echo "$TAILSCALE_IP"

echo
echo "======================================"
echo " Setup complete! ✅"
echo "======================================"
echo
echo "noVNC:  https://7902-cs-717088098702-default.cs-asia-southeast1-ajrg.cloudshell.dev"
echo "VNC:    $TAILSCALE_IP:5901"
echo
