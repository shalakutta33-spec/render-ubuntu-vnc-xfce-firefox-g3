```bash
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

    docker exec -it "$CONTAINER" tailscale-login

elif echo "$STATUS" | grep -q "Tailscale is stopped"; then

    echo
    echo "Tailscale daemon is not ready."
    echo
    echo "Run:"
    echo "docker exec -it $CONTAINER tailscale-login"
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
docker exec "$CONTAINER" tailscale ip -4

echo
echo "======================================"
echo " Setup complete! ✅"
echo "======================================"
echo
echo "noVNC:  http://localhost:7902"
echo "VNC:    Tailscale-IP:5901"
echo
```
