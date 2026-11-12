# netlify-proxy

Routes a small set of blackholed Netlify CDN addresses through a Cloudflare WARP
tunnel (MASQUE), while leaving every other route on the machine untouched.

Built for the Egypt-specific case where `*.netlify.app` and Netlify-hosted custom
domains resolve correctly but their edge IPs are silently dropped at TCP connect.

## What it does and does not touch

| | |
|---|---|
| adds | `/32` routes for the IPs in `routes/netlify-ips.txt`, via `dev usque` |
| leaves alone | default route, gateway, DNS, `resolv.conf`, all other traffic |
| on stop | interface is destroyed, kernel drops the `/32`s automatically |

No secrets are stored in the image or the compose file. The WARP registration
lives in `./config/config.json` on the host and is mounted **read-only**.

## Requirements

- Linux host (host-network TUN does not work under Docker Desktop on macOS/Windows)
- Docker with the compose plugin
- `/dev/net/tun` present (`sudo modprobe tun` if missing)
- `NET_ADMIN` capability for the container

## Install

```bash
cd ~/projects/netlify-proxy
./install.sh
```

The script checks prerequisites, refuses to start if another tunnel already owns
the `usque` interface, builds the image, registers a WARP account once, starts the
container, then verifies each route and that the default route is untouched.

## Verify

```bash
docker compose ps
ip route get 63.176.8.218    # -> dev usque
ip route get 1.1.1.1         # -> via <your gateway>, dev <your nic>
curl -sI https://biomejs.dev | head -1
```

## Updating the address list

Netlify rotates edge IPs occasionally. Re-discover and edit the list:

```bash
getent ahostsv4 biomejs.dev | awk '{print $1}' | sort -u
dig +short netlify.app A
$EDITOR routes/netlify-ips.txt
docker compose restart
```

No rebuild needed — `routes/` is mounted, not copied.

## Logs

```bash
docker compose logs -f
```

Look for `applied N route(s) to usque` from the hook after each connect.

## Uninstall

```bash
./uninstall.sh           # remove container + image, keep the registration
./uninstall.sh --purge   # also delete config/ (destroys the WARP identity)
```

## Troubleshooting

**`interface 'usque' already exists`** — a previous tunnel (for example a
`usque-tun.service` unit) still owns it:

```bash
sudo systemctl disable --now usque-tun.service
./install.sh
```

**`cannot reach the docker daemon`** — your user is not in the `docker` group, or
the session predates the group change: `newgrp docker`.

**Container restarts in a loop** — read `docker compose logs`. Most common cause is
a missing or unreadable `config/config.json`.

**Sites work but HTTPS fails on some domains** — those hosts may resolve to
additional Netlify IPs; add them to `routes/netlify-ips.txt` and restart.

## Security notes

`network_mode: host` plus `NET_ADMIN` is close to root-equivalent control of the
host's networking. The container is otherwise hardened: read-only root filesystem,
`no-new-privileges`, no secrets in the image, and an unprivileged-US layout is not
possible for this design. If that trade is unacceptable on a given machine, use the
`l4-socks` mode instead and proxy only the affected domains.
