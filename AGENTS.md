# Agent instructions — netlify-proxy

This repo is a small, high-blast-radius piece of infrastructure: it manipulates
the host's routing table. Read this before changing anything.

## Testing rules

These exist because three successive "verified" claims here were wrong. Each bug
lived in the one code path that was never actually executed.

### 1. Run the entry point the user runs

For installer changes, the test is `./install.sh` and `./uninstall.sh`. Building
the image, parsing the compose file, or invoking `docker compose up` manually
proves nothing about the installer.

A clean cycle must pass end to end before reporting success:

```bash
./uninstall.sh
./install.sh
```

Never report "verified" on the strength of component checks. If the entry point
cannot be run (state conflict, missing privilege), say so and report the change as
untested rather than verified.

### 2. Test through the real invocation path

usque launches hooks with `execve`, directly, with no shell fallback. Testing a
hook like this proves nothing:

```bash
sh -c /usr/local/bin/usque-up.sh          # WRONG: shells fall back on ENOEXEC
```

Test it the way the product does — either the real tunnel, or a direct exec:

```bash
docker run --rm --entrypoint /bin/sh netlify-proxy:local -c '/usr/local/bin/usque-up.sh'
```

The first two shell shebangs must be present. Any script invoked by usque needs a
shebang; a missing one fails at runtime with the opaque `exec format error`.

### 3. Assert end state, not precursors

Events happen in this order, all within about one second:

```
TUN device created  ->  MASQUE handshake  ->  hook[connect]  ->  routes present
```

So "interface exists" is true well before "routes are applied". Poll for the thing
that matters:

```bash
ip route get 63.176.8.218 | grep -q 'dev usque'
```

not for the interface. Existing helpers: `routed_via_iface` in `install.sh`.

### 4. Verify after destructive or stateful operations

Routing changes are global and silent. After any change, confirm all four:

```bash
ip route get 35.157.26.135      # -> dev usque
ip route get 63.176.8.218       # -> dev usque
ip route get 1.1.1.1            # -> via <gateway>, dev <nic>   (must NOT be usque)
curl -s -o /dev/null -w '%{http_code}\n' https://biomejs.dev   # -> 200
```

## Invariants

- Only the `/32`s listed in `routes/netlify-ips.txt` are routed through the tunnel.
- The default route, gateway, DNS, and `resolv.conf` are never modified.
- `config/` holds the WARP registration and is git-ignored. It is mounted
  read-only at runtime and must never be baked into the image.
- One tunnel per host: `usque-tun.service` (systemd) and this container both claim
  the `usque` interface. `install.sh` refuses to start if either is present.

## Environment notes

- `sudo` requires a password here and cannot read it from a redirected stdin, so
  `sudo cmd <<'EOF'` heredocs fail. Write files to `/tmp` and `sudo install` them.
- Docker is usable as the normal user (docker group); the installer needs no sudo.
- `read_only: true` on the container is deliberate. If the container loops with a
  filesystem error, that is the line to revisit, not the volume mounts.

## Style

- Shell: `sh` for anything run inside the container (alpine/busybox), `bash` for
  host scripts. `set -eu` at minimum; `set -euo pipefail` for bash.
- Fail loudly. A hook that cannot apply routes must exit non-zero, not continue.
- Keep the blast radius explicit: any new route, firewall rule, or DNS change must
  be justified in the PR/commit message.
