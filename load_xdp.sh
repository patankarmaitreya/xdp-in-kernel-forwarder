#!/usr/bin/env bash
set -euo pipefail

BPFTOOL=/usr/lib/linux-tools-6.8.0-147/bpftool
MAP_DIR=/sys/fs/bpf/xdp_maps
PROG_PIN=/sys/fs/bpf/xdp_ipv4_mac_lookup

# Reuse the existing maps.
cmd=(
    "$BPFTOOL" prog load xdp_pass.bpf.o "$PROG_PIN"
    type xdp
    map name routing_table pinned "$MAP_DIR/routing_table"
    map name route_stats pinned "$MAP_DIR/route_stats"
    map name local_ip_map pinned "$MAP_DIR/local_ip_map"
    map name arp_cache pinned "$MAP_DIR/arp_cache"
)

# Reuse the interface MAC map after we have pinned it.
if [[ -e "$MAP_DIR/interface_mac_map" ]]; then
    cmd+=(
        map name interface_mac_map
        pinned "$MAP_DIR/interface_mac_map"
    )
fi

# Remove only the old program pin, if present.
if [[ -e "$PROG_PIN" ]]; then
    rm "$PROG_PIN"
fi

"${cmd[@]}"

echo "XDP program loaded successfully"
"$BPFTOOL" prog show pinned "$PROG_PIN"