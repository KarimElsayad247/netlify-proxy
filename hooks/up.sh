# Purpose: apply per-IP routes for the blackholed Netlify edge addresses to the
# usque TUN interface. Invoked by usque after every successful tunnel connect.
# Runs in the host network namespace, as root, with NET_ADMIN.
set -eu

IFACE="${USQUE_IFACE:?USQUE_IFACE is unset, refusing to guess an interface}"
ROUTES_FILE="${ROUTES_FILE:-/etc/usque-routes/netlify-ips.txt}"

[ -r "$ROUTES_FILE" ] || {
    echo "routes file not readable: $ROUTES_FILE" >&2
    exit 1
}

applied=0
while IFS= read -r line || [ -n "$line" ]; do
    entry="${line%%#*}"
    entry="$(printf '%s' "$entry" | tr -d '[:space:]')"
    [ -n "$entry" ] || continue

    case "$entry" in
        *[!0-9.]*)
            echo "skipping invalid entry: $entry" >&2
            continue
            ;;
    esac

    /sbin/ip route replace "$entry/32" dev "$IFACE"
    applied=$((applied + 1))
done < "$ROUTES_FILE"

echo "applied $applied route(s) to $IFACE"
