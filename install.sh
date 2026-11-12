#!/usr/bin/env bash
# Purpose: build, register (once) and start the netlify-proxy tunnel container.
# Modifies nothing on the host except the routes for the IPs in routes/netlify-ips.txt.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

IMAGE=netlify-proxy:local
IFACE=usque
ROUTES_FILE="$HERE/routes/netlify-ips.txt"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight ---
step "checking prerequisites"

command -v docker >/dev/null 2>&1 \
    || die "docker not found"
docker info >/dev/null 2>&1 \
    || die "cannot reach the docker daemon (group membership? try 'newgrp docker')"
docker compose version >/dev/null 2>&1 \
    || die "docker compose plugin not found"

[ -e /dev/net/tun ] \
    || die "/dev/net/tun is missing; load the module with: sudo modprobe tun"

command -v ip >/dev/null 2>&1 \
    || die "iproute2 not found on the host (needed for verification)"

[ -s "$ROUTES_FILE" ] \
    || die "missing or empty: $ROUTES_FILE"

grep -qvE '^[[:space:]]*(#|$)' "$ROUTES_FILE" \
    || die "no addresses listed in $ROUTES_FILE"

# Refuse to start if another tunnel already owns the interface.
if systemctl is-active --quiet usque-tun.service 2>/dev/null; then
    die "usque-tun.service is active and owns interface '$IFACE'.
       Stop it first: sudo systemctl disable --now usque-tun.service"
fi
if ip link show "$IFACE" >/dev/null 2>&1; then
    die "interface '$IFACE' already exists; stop whatever created it first"
fi

# ------------------------------------------------------------------- build ---
step "building $IMAGE"
docker compose build

# -------------------------------------------------------------- register ----
mkdir -p config
chmod 700 config

if [ -s config/config.json ] && grep -q '"license"' config/config.json; then
    step "existing registration found, reusing config/config.json"
else
    step "registering a new WARP account (one-time, network access required)"
    docker run --rm -v "$HERE/config:/etc/usque" "$IMAGE" \
        -c /etc/usque/config.json register -n "$(hostname)" --accept-tos
    [ -s config/config.json ] || die "registration did not produce config/config.json"
fi

chmod 700 config
chmod 600 config/config.json 2>/dev/null || true

# ------------------------------------------------------------------- start ---
step "starting container"
docker compose up -d --remove-orphans

step "waiting for the tunnel interface"
for _ in $(seq 1 40); do
    ip link show "$IFACE" >/dev/null 2>&1 && break
    sleep 1
done
ip link show "$IFACE" >/dev/null 2>&1 \
    || die "interface '$IFACE' never appeared; see: docker compose logs"

# ------------------------------------------------------------------ verify ---
step "verifying routes"
failed=0

while IFS= read -r line || [ -n "$line" ]; do
    entry="${line%%#*}"
    entry="$(printf '%s' "$entry" | tr -d '[:space:]')"
    [ -n "$entry" ] || continue
    case "$entry" in *[!0-9.]*) continue ;; esac

    if ip route get "$entry" 2>/dev/null | head -1 | grep -q "dev $IFACE"; then
        printf '  ok    %-16s via %s\n' "$entry" "$IFACE"
    else
        printf '  FAIL  %-16s not routed via %s\n' "$entry" "$IFACE"
        failed=1
    fi
done < "$ROUTES_FILE"

# Guard against the tunnel ever capturing the default route.
if ip route show default | grep -q "dev $IFACE"; then
    printf '  FAIL  default route points at %s\n' "$IFACE"
    failed=1
else
    printf '  ok    default route untouched\n'
fi

[ "$failed" -eq 0 ] || die "verification failed; see: docker compose logs"

step "checking a blackholed site end to end"
if command -v curl >/dev/null 2>&1; then
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 https://biomejs.dev || true)
    printf '  biomejs.dev -> HTTP %s\n' "${code:-no response}"
    [ "$code" = "200" ] || printf '  warning: unexpected status; check docker compose logs\n'
fi

step "done"
printf 'Container status:\n'
docker compose ps
printf '\nUpdate the address list in %s, then: docker compose restart\n' "$ROUTES_FILE"
printf 'Remove everything with: %s/uninstall.sh\n' "$HERE"
