#!/usr/bin/env bash
# Purpose: stop and remove the netlify-proxy container. Routes disappear with the
# TUN interface, so the host network is restored automatically.
#
#   ./uninstall.sh          remove container and image, keep the registration
#   ./uninstall.sh --purge  also delete config/ (destroys the WARP identity)
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"

IMAGE=netlify-proxy:local
IFACE=usque

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "stopping container"
if docker compose version >/dev/null 2>&1; then
    docker compose down --remove-orphans || true
else
    docker rm -f netlify-proxy 2>/dev/null || true
fi

step "waiting for interface '$IFACE' to disappear"
for _ in $(seq 1 20); do
    ip link show "$IFACE" >/dev/null 2>&1 || break
    sleep 1
done

if ip link show "$IFACE" >/dev/null 2>&1; then
    printf 'warning: %s still exists (left by another process?)\n' "$IFACE"
else
    echo "  interface removed"
fi

step "removing image"
docker image rm "$IMAGE" >/dev/null 2>&1 && echo "  removed $IMAGE" || echo "  image not present"

if [ "${1:-}" = "--purge" ]; then
    step "deleting registration"
    rm -rf -- "$HERE/config"
    echo "  removed $HERE/config"
else
    [ -d "$HERE/config" ] && printf '\nRegistration kept in %s\nPass --purge to delete it.\n' "$HERE/config"
fi

step "done"
printf 'Default route check:\n'
ip route show default
