#!/usr/bin/env bash
set -euo pipefail

# Retrieve interface indices from the router namespace.
get_ifindex() {
    local iface="$1"

    sudo ip -n labR -o link show dev "$iface" |
        awk -F: 'NR == 1 {
            gsub(/[[:space:]]/, "", $1)
            print $1
        }'
}

LEFT_IFINDEX=$(get_ifindex router-left)
RIGHT_IFINDEX=$(get_ifindex router-right)

if [[ ! "$LEFT_IFINDEX" =~ ^[0-9]+$ ||
      ! "$RIGHT_IFINDEX" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Failed to retrieve interface indices" >&2
    exit 1
fi

# Generate routes for the current topology.
cat > routes.conf <<EOF
10.0.1.0/24 0.0.0.0 $LEFT_IFINDEX 1
10.0.2.0/24 0.0.0.0 $RIGHT_IFINDEX 1
EOF

echo "Generated routes.conf:"
cat routes.conf