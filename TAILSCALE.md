# Tailscale — every error we hit, cause, exact fix

## 0. The one rule

`tailscale up` is only the **client**. It needs the **daemon** (`tailscaled`)
already running behind it. 90% of all Tailscale errors = daemon not running.
Containers have **no `systemd`**, so `sudo systemctl start tailscaled` can
never work inside them — start the daemon by hand instead.

## 1. Error: `failed to connect to local tailscaled`

Full text:

```
failed to connect to local tailscaled; it doesn't appear to be running
(sudo systemctl start tailscaled ?)
```

**Cause:** nothing is listening on the daemon socket. Either `tailscaled`
was never started, or it started and **exited immediately** (then the real
error is 2–3 lines above in its output — always read those first).

**Fix:** start the daemon first, then `up`:

```bash
tailscaled --tun=userspace-networking &
sleep 3
tailscale up
```

Verify: `tailscale ip -4` → `100.x`, `tailscale status` → `Logged in`.

## 2. Error: daemon exits — TUN problems

Typical lines just before exit:

```
tstun.New("tailscale0"): CreateTUN("tailscale0") failed;
/dev/net/tun does not exist
```
```
wgengine.NewUserspaceEngine(tun "tailscale0") error:
tstun.New("tailscale0"): operation not permitted
```
```
is CONFIG_TUN enabled in your kernel? `modprobe tun` failed
```

**Cause:** normal TUN mode needs `/dev/net/tun` + `NET_ADMIN` capability.
Plain containers / Render Free / LXC / some CI runners don't have them.

**Fix:** userspace networking (no TUN, no root needed):

```bash
tailscaled --tun=userspace-networking &
```

This is what our `start.sh` uses on Render, and what the Tailscale docs
([userspace networking](https://tailscale.com/kb/1112/userspace-networking))
prescribe for containers. Confirmed by
[tailscale#16893](https://github.com/tailscale/tailscale/issues/16893) (LXC,
fix = allow `/dev/net/tun`),
[tailscale/github-action#286](https://github.com/tailscale/github-action/issues/286)
(fix = `tailscaled-args: --tun=userspace-networking`),
[kasmtech/workspaces-images#129](https://github.com/kasmtech/workspaces-images/issues/129)
(same error in Docker → needs `NET_ADMIN` + `/dev/net/tun`, else userspace).

Trade-off: userspace mode can't do exit-nodes / subnet routes from that
node; plain tailnet ping/serve/VNC works fine.

## 3. Error: daemon exits — socket bind failure (non-root user)

```
safesocket.Listen: listen unix /var/run/tailscale/tailscaled.sock:
bind: no such file or directory
[1]+ Exit 1  tailscaled --tun=userspace-networking
```

**Cause:** you run as a normal user (`abc`), the default socket dir
`/var/run/tailscale` doesn't exist and you can't create it. (Same for the
default state dir if `$HOME` is odd.)

**Fix:** put socket + state somewhere you own:

Then log in — TWO separate ways, pick one (each block is complete,
daemon start included, copy-paste as-is):

> TL;DR: plain `tailscale up` = connect via link, log into your account in
> the browser to approve; `tailscale up --auth-key=...` = auto-connect, no
> link, no login, no hassle.

**Option 1 — manual (interactive, no key needed):**

```bash
mkdir -p /tmp/ts
tailscaled --tun=userspace-networking \
  --socket=/tmp/ts/tailscaled.sock \
  --state=/tmp/ts/tailscaled.state &
sleep 3
tailscale --socket=/tmp/ts/tailscaled.sock up
```

It prints a browser URL. Open that URL on any device already logged into
your tailnet (phone/laptop) to approve. Good for one-off machines where
you sit at the keyboard.

**Option 2 — auth key (auto-connect, no browser):**

```bash
mkdir -p /tmp/ts
tailscaled --tun=userspace-networking \
  --socket=/tmp/ts/tailscaled.sock \
  --state=/tmp/ts/tailscaled.state &
sleep 3
tailscale --socket=/tmp/ts/tailscaled.sock up --auth-key=tskey-auth-XXXX
```

Connects immediately with zero clicks. Required for headless hosts
(Render, CI, Docker without a browser). Get the key from Tailscale admin
→ Settings → Keys → Auth key (use reusable + ephemeral so redeploys
don't pile up offline nodes).

**Rule after that:** EVERY `tailscale` call needs the flag:
`tailscale --socket=/tmp/ts/tailscaled.sock status|ip|logout|...`
Forgetting it gives back error §1 (it looks at the wrong path).

## 4. Problem: CLI talks to the wrong socket

Error 1 (wrong socket):

```
Failed to connect to local Tailscale daemon for /localapi/v0/status; not running? Error: dial unix /var/run/tailscale/tailscaled.sock: connect: no such file or directory
```

Means: CLI looked for the daemon at the default socket
`/var/run/tailscale/tailscaled.sock`, nothing there — ours listens on
`/tmp/tailscaled.sock` (Render) or `/tmp/ts/tailscaled.sock` (non-root
setup). Daemon is running; CLI just knocked on the wrong door.

Solution code — add `--socket=` with the real path to every command:

```bash
tailscale --socket=/tmp/tailscaled.sock status
tailscale --socket=/tmp/tailscaled.sock ip -4
tailscale --socket=/tmp/tailscaled.sock set --ssh
```

No output after `set --ssh` = success. Then from any tailnet device:
`tailscale ssh ubuntu-firefox-23`.

## 5. Problem: pasted command not found

Error 2 (bad paste):

```
bash: $'\E[200~tailscale': command not found
```

Means: pasted text carried terminal bracketed-paste control codes
(`ESC[200~`, shown as `^[[200~`) plus a trailing `~`, so bash treated the
whole blob as the command name. Not a Tailscale problem — a terminal
paste glitch.

Solution code — press `Ctrl+C`, retype cleanly with no `~`:

```bash
tailscale --socket=/tmp/tailscaled.sock set --ssh
```

## 6. Problem: `tailscale ssh` hangs forever, no output

Error 3 (SSH hang): you run

```bash
tailscale ssh ubuntu-firefox-26
```

and nothing happens — no prompt, no error, just sits until timeout.
Meanwhile `tailscale ping --c=3 ubuntu-firefox-26` answers fine:

```
pong from ubuntu-firefox-26 (100.88.32.16) via DERP(sea) in 257ms
```

Means: L3 (WireGuard) is healthy — ping proves packets flow. The SSH
layer (L7) never answers. Diagnose in this order, by running:

1. `tailscale --socket=/tmp/tailscaled.sock debug prefs | grep -i ssh`
   → expect `"RunSSH": true`. If false, the server flag never got set
   (our `start.sh` runs `tailscale ... set --ssh` on every boot so it
   survives restarts; a hand-run `set --ssh` dies with the container).
2. If `RunSSH` is true, the block is your tailnet **SSH access rule**.
   Ours was:

```json
{
	"action": "check",
	"src":    ["autogroup:member"],
	"dst":    ["autogroup:self"],
	"users":  ["autogroup:nonroot", "root"],
}
```

`"action": "check"` = check mode: every new client must be approved ON
the target device before SSH opens. A headless container has nobody to
click approve → dial hangs forever. That was our exact hang.

Solution code — admin → Access controls, flip `check` to `accept`:

```json
{
	"action": "accept",
	"src":    ["autogroup:member"],
	"dst":    ["autogroup:self"],
	"users":  ["autogroup:nonroot", "root"],
}
```

Save, wait a minute, retry `tailscale ssh ubuntu-firefox-26` → drops
straight into a shell. Verify inside with `whoami; hostname`.

## 7. Problem: SSH disabled — `no var root for ssh keys`

Error 4 (SSH host keys missing) — in deploy logs after boot:

```
warning: unable to get SSH host keys, SSH will appear as disabled for
this node: no var root for ssh keys
```

Means: `RunSSH=true` was set, but the daemon had nowhere writable to
store SSH host keys. Tailscale's default var root (`/var/lib/tailscale`)
isn't usable inside this container, so the daemon silently advertised
SSH as **disabled** — dials hung forever with zero server-side `SSH:`
lines, even with the ACL on `accept` and ping working. This was the
deeper cause underneath §6: fixing the ACL alone couldn't help while the
server had no host keys.

Solution code — where: `start.sh`, the `tailscaled` launch line. Give the
daemon a writable state dir:

```bash
mkdir -p /tmp/ts-var
tailscaled --tun=userspace-networking \
  --state=/tmp/tailscaled.state \
  --statedir=/tmp/ts-var \
  --socket=/tmp/tailscaled.sock >/tmp/tailscaled.log 2>&1 &
```

What changed: one added flag, `--statedir=/tmp/ts-var` (plus `mkdir`).
Pushed as `07653eb`, redeploy, and the `no var root` warning disappears —
`tailscale ssh root@ubuntu-firefox-2N` then lands in a shell.

## 8. Harmless lines (ignore these)

| Line | Meaning |
|---|---|
| `TPM: error opening: stat /dev/tpmrm0` | no hardware TPM in container. Ignore. |
| `magicsock: failed to force-set UDP buffer ... operation not permitted` | can't raise kernel buffers unprivileged. Throughput only. |
| `tstun: error initializing tun dev stats polling` | expected under userspace mode. |
| `dns: using dns.noopManager / directManager` | no system DNS control in container. Normal. |
| `peerapi: unknown peer 127.0.0.1` (+ RATELIMIT) | something (Render health checks) probing Tailscale's local API port. Noise. |
| `logtail: upload ... failed 429` | Tailscale's own telemetry rate-limited. Ignore. |
| ` flushing log. / logger closing down` after an error | daemon shutting down because of the real error above — read upward, not these. |

## 9. Exact sequences (copy-paste)

### A. Container as root (Docker `root@...`, Render shell)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscaled --tun=userspace-networking &
sleep 3
tailscale up
```

Headless (needs key, no browser):

```bash
curl -fsSL https://tailscale.com/install.sh | sh && (tailscaled --tun=userspace-networking >/tmp/tailscaled.log 2>&1 & sleep 3; tailscale up --auth-key=tskey-auth-XXXX)
```

### B. Container/VM as normal user (`abc@...`, no root)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
mkdir -p /tmp/ts
tailscaled --tun=userspace-networking --socket=/tmp/ts/tailscaled.sock --state=/tmp/ts/tailscaled.state &
sleep 3
tailscale --socket=/tmp/ts/tailscaled.sock up
```

One-liner:

```bash
curl -fsSL https://tailscale.com/install.sh | sh && mkdir -p /tmp/ts && (tailscaled --tun=userspace-networking --socket=/tmp/ts/tailscaled.sock --state=/tmp/ts/tailscaled.state >/tmp/ts/tailscaled.log 2>&1 & sleep 3; tailscale --socket=/tmp/ts/tailscaled.sock up)
```

### C. This repo on Render (`start.sh` already does it)

Socket is `/tmp/tailscaled.sock`, state `/tmp/tailscaled.state`. In Shell:

```bash
tailscale --socket=/tmp/tailscaled.sock status
tailscale --socket=/tmp/tailscaled.sock ip -4
tailscale --socket=/tmp/tailscaled.sock set --ssh
```

Enable SSH (no output = success), then connect from any tailnet device:

```bash
tailscale ssh ubuntu-firefox-23
```

## 10. Auth keys

* Interactive `tailscale up` prints a browser URL — open it on a logged-in
  device. Works once.
* Headless/CI/Render: Tailscale admin → Settings → Keys → **Auth key** →
  `tailscale up --auth-key=tskey-auth-...`.
* Every fresh container registers a NEW node (`ubuntu-firefox-23` = 23rd).
  Old ones go `offline` — delete them in admin. Use a **reusable +
  ephemeral** key so redeploys don't pile up offline nodes.
* Our Render node showed `100.94.192.45` (`ubuntu-firefox-23`); IP changes
  per deploy — use MagicDNS (`ubuntu-firefox.<tailnet>.ts.net`) or check
  `ip -4` after each deploy.

## 11. How we debugged this session (order)

1. Ran `tailscale up` → got Error §1 (`failed to connect to local
   tailscaled`). That only says "no daemon on the socket" — not WHY.
2. Started the daemon in foreground (`tailscaled --tun=userspace-networking`,
   no `&`) and read the FIRST error lines at the top of its output
   (not the `flushing log / logger closing down` tail). Top line was the
   socket `bind: no such file or directory` (§3) — that named the real
   cause; everything below was just shutdown noise.
3. Fixed it with these exact commands (socket+state moved somewhere owned):

```bash
mkdir -p /tmp/ts
tailscaled --tun=userspace-networking \
  --socket=/tmp/ts/tailscaled.sock \
  --state=/tmp/ts/tailscaled.state &
sleep 3
tailscale --socket=/tmp/ts/tailscaled.sock up
```

Confirmed: `tailscale --socket=/tmp/ts/tailscaled.sock status` → daemon
answered → `tailscale --socket=/tmp/ts/tailscaled.sock ip -4` → `100.x`
→ `status: Logged in`. Done.

Rule: `tailscale up` shows the symptom; the daemon's own first lines
(or `tailscale --socket=<real> status` answering vs refusing) show the
cause.
