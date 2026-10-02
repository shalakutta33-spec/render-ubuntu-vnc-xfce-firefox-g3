# Deploy on Render — ubuntu-vnc-xfce-g3

Desktop (XFCE + Firefox) in Docker, served via noVNC on Render Free.

Live URL pattern: `https://<service>.onrender.com` → noVNC landing →
`vnc.html` = Full Client (use this).

## 1. Create the service

1. Render Dashboard → `New` → `Web Service`
2. `Build and deploy from a GitHub repository` → select
   `shalakutta33-spec/render-ubuntu-vnc-xfce-firefox-g3`, branch `main`
3. Settings:
   - `Environment`: `Docker`
   - `Dockerfile Path`: `./Dockerfile`
   - `Instance Type`: `Free` (works; spins down when idle ~50s cold start)
4. `Create Web Service` → first deploy starts automatically.

## 2. Environment variables

| Key | Required? | Value | Notes |
|---|---|---|---|
| `TS_AUTHKEY` | Only for Tailscale | `tskey-auth-...` (from Tailscale admin → Settings → Keys → Auth key) | If empty/unset, Tailscale is skipped, VNC still boots. Use a **reusable + ephemeral** key, else every redeploy registers a new `ubuntu-firefox-N` node and old ones pile up as offline. |
| `VNC_PW` | No | `headless` | VNC/noVNC password. If unset, defaults to `headless`. Use it in `vnc.html?password=...` and in the password box. |
| `PORT` | **DO NOT SET — delete the row** | (Render injects `10000` itself) | `start.sh` maps `NOVNC_PORT=$PORT` automatically. Setting `PORT=6901` manually worked but fights Render's default — leave it empty. |
| `VNC_PORT` / `NOVNC_PORT` | No | defaults `5901` / `$PORT` | Never set these on Render. `5901` is **internal only** (TigerVNC backend). Only `$PORT` (noVNC) is public. `EXPOSE` lines in the Dockerfile are ignored by Render. |
| `VNC_RESOLUTION` | No | `1360x768` | e.g. `1280x800`. Applied on next deploy (config is written at container start). |
| `VNC_COL_DEPTH` | No | `24` | Leave it. |
| `NOVNC_HEARTBEAT` | No | `30` | Already defaulted in `start.sh`. Keeps the websocket alive behind Render's proxy. |

## 3. How it works (so logs make sense)

`start.sh` (rootless, no `sudo`) does, in order:

1. Tailscale (skipped if no `TS_AUTHKEY`):
   `tailscaled --tun=userspace-networking --state=/tmp/tailscaled.state
   --socket=/tmp/tailscaled.sock`, then `tailscale up`. Socket is
   `/tmp/tailscaled.sock` — **not** the default
   `/var/run/tailscale/tailscaled.sock`, so every CLI call needs
   `tailscale --socket=/tmp/tailscaled.sock ...`.
2. Writes TigerVNC config (`$VNC_CONFIG_HOME/config` = `rfbport, depth,
   geometry, BlacklistTimeout=0`) + password file via `vncpasswd`.
3. `vncserver :1` → Xvnc listens on `5901` (internal).
4. `novnc_proxy --vnc localhost:5901 --listen $PORT` → public web on `$PORT`.
5. Tails `vnc.log + novnc.log + tailscaled.log` to stdout so Render shows them.

## 4. Test it

* Landing: `https://<service>.onrender.com/` → links to Lite/Full clients.
* Direct: `https://<service>.onrender.com/vnc.html?autoconnect=true&password=headless`
  (replace `headless` with your `VNC_PW`).
* Success = XFCE desktop (top bar, Firefox icon, blue mouse wallpaper).
* `Failed to connect to server` = page loaded but VNC backend down — read §5.

## 5. Troubleshooting (every error we hit)

* `user_generator.rc line 98: .initial_sudo_password: Permission denied` +
  `Unable to generate user '1001:1001'` → old image path. Fixed by
  `chmod 666 /dockerstartup/.initial_sudo_password + 777 /dockerstartup +
  666 /etc/passwd/group` in Dockerfile. Should not reappear.
* `sudo: unable to send audit message` → harmless container noise. Ignore.
* `Failed to connect to server` on `vnc.html`:
  1. Wrong password shows `Authentication failed`, NOT this. This error =
     websocket/TCP level → VNC backend down.
  2. Cause we found: TigerVNC blacklisted `127.0.0.1` because Render's port
     scanner probes `5901` with non-RFB data (`Reading version failed` /
     `Clean disconnection`). Blacklist also blocked websockify (same IP).
     Fixed by `BlacklistTimeout=0` in tigervnc config.
  3. Remaining `Reading version failed / Clean disconnection` lines every
     second = Render scanner noise. Ignore as long as no `Blacklisted` line.
* `Detected new open ports HTTP:6901 / TCP:5901` → informational. Only
  `$PORT` matters.
* `magicsock: failed to force-set UDP buffer` / `tstun: error initializing
  tun dev stats` / `peerapi: unknown peer 127.0.0.1` → harmless sandbox
  noise. Ignore.
* `It looks like we don't have access to your repo` at build start →
  harmless warning Render prints on public repos; clone still succeeds.
* Free plan: no Shell/SSH (needs Starter+), instance sleeps on idle, logs
  kept briefly. Shell in this repo's history ran as `root@...` on a paid
  plan — on Free use Logs tab only.

## 6. Tailscale (tailnet access)

* With `TS_AUTHKEY` set, node registers as `ubuntu-firefox[-N]`:
  check with `tailscale --socket=/tmp/tailscaled.sock status`,
  IP with `tailscale --socket=/tmp/tailscaled.sock ip -4` (a `100.x`).
* From any tailnet device (your phone/desktop online in `status`):
  browser → `http://100.x:10000/vnc.html` (password = `VNC_PW`),
  or VNC viewer → `100.x:5901`.
* IP/hostname changes each deploy (`-23` = 23rd registration). Fix: delete
  dead `ubuntu-firefox-N` offline nodes in Tailscale admin, use an
  ephemeral+reusable key, and use MagicDNS
  (`ubuntu-firefox.<tailnet>.ts.net`) instead of raw IP.

## 7. Redeploy checklist

1. `git push origin main` (repo) → Render auto-deploys, or Dashboard →
   `Manual Deploy` → `Deploy latest commit`.
2. Wait for `Deploy succeeded | Live` + `Available at your primary URL`.
3. Hard-refresh `vnc.html` (free instances sleep; first load can take ~50s).
