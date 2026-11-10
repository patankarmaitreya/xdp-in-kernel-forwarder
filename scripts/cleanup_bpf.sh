#!/usr/bin/env bash
set -euo pipefail

MAP_DIR=/sys/fs/bpf/xdp_maps
PROG_PIN=/sys/fs/bpf/xdp_ipv4_mac_lookup

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root"
    exit 1
fi

# Never remove pins while the router namespace exists.
if ip netns list | grep -Eq '^labR([[:space:]]|$)'; then
    echo "ERROR: labR still exists. Tear down the lab first."
    exit 1
fi

# Remove the pinned program.
if [[ -e "$PROG_PIN" ]]; then
    rm -- "$PROG_PIN"
    echo "Removed pinned XDP program"
fi

# Remove only this project's known map pins.
for map in \
    routing_table \
    route_stats \
    local_ip_map \
    arp_cache \
    interface_mac_map \
    xdp_pass_rodata
do
    if [[ -e "$MAP_DIR/$map" ]]; then
        rm -- "$MAP_DIR/$map"
        echo "Removed map pin: $map"
    fi
done

echo "BPF pin cleanup completed"