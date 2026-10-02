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

```
Failed to connect to local Tailscale daemon for /localapi/v0/status;
not running? Error: dial unix /var/run/tailscale/tailscaled.sock:
connect: no such file or directory
```

**What's the problem:** the daemon IS running, but on a custom socket
(e.g. `/tmp/tailscaled.sock` on Render, `/tmp/ts/tailscaled.sock` for
non-root users). The CLI defaults to `/var/run/tailscale/tailscaled.sock`,
finds nothing there, and reports "not running".

**Fix:** point every command at the real socket:

```bash
tailscale --socket=/tmp/tailscaled.sock status
tailscale --socket=/tmp/tailscaled.sock ip -4
tailscale --socket=/tmp/tailscaled.sock set --ssh
```

No output after `set --ssh` = success. Then from any tailnet device:
`tailscale ssh ubuntu-firefox-23`.

## 5. Problem: pasted command not found

```
bash: $'\E[200~tailscale': command not found
```

**What's the problem:** the paste carried terminal bracketed-paste control
codes (`ESC[200~` shown as `^[[200~`) plus a trailing `~`, so bash treated
the whole blob as the command name. Not a Tailscale problem at all — a
terminal paste glitch.

**Fix:** press `Ctrl+C`, retype the command cleanly by hand with no
trailing `~`:

```bash
tailscale --socket=/tmp/tailscaled.sock set --ssh
```

## 6. Harmless lines (ignore these)

| Line | Meaning |
|---|---|
| `TPM: error opening: stat /dev/tpmrm0` | no hardware TPM in container. Ignore. |
| `magicsock: failed to force-set UDP buffer ... operation not permitted` | can't raise kernel buffers unprivileged. Throughput only. |
| `tstun: error initializing tun dev stats polling` | expected under userspace mode. |
| `dns: using dns.noopManager / directManager` | no system DNS control in container. Normal. |
| `peerapi: unknown peer 127.0.0.1` (+ RATELIMIT) | something (Render health checks) probing Tailscale's local API port. Noise. |
| `logtail: upload ... failed 429` | Tailscale's own telemetry rate-limited. Ignore. |
| ` flushing log. / logger closing down` after an error | daemon shutting down because of the real error above — read upward, not these. |

## 7. Exact sequences (copy-paste)

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

## 8. Auth keys

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

## 9. How we debugged this session (order)

1. `tailscale up` → §1 error → daemon not running.
2. Started daemon bare → exited, top error = socket `bind: no such file` (§3),
   not TUN (§2) — because user was non-root.
3. Moved socket+state to `/tmp/ts` → daemon stayed up → `tailscale up`
   → `100.x` → `status: Logged in`. Done.
