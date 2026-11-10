#!/usr/bin/env bash
set -euo pipefail

BPFTOOL=/usr/lib/linux-tools-6.8.0-147/bpftool
MAP_DIR=/sys/fs/bpf/xdp_maps

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root"
    exit 1
fi

# Ensure the routing table exists.
if [[ ! -e "$MAP_DIR/routing_table" ]]; then
    echo "ERROR: Routing table is not initialized"
    exit 1
fi

# Populate routing entries from routes.conf.
./route_loader

echo "Routing table populated successfully"

set_local_ip() {
    local ip="$1"
    local iface="$2"
    local ifindex

    ifindex=$(ip -n labR -o link show dev "$iface" |
        awk -F: 'NR == 1 {
            gsub(/[[:space:]]/, "", $1)
            print $1
        }')

    if [[ ! "$ifindex" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Cannot determine ifindex for $iface" >&2
        return 1
    fi

    IFS=. read -r a b c d <<< "$ip"

    "$BPFTOOL" map update pinned "$MAP_DIR/local_ip_map" \
        key hex \
        "$(printf '%02x' "$a")" \
        "$(printf '%02x' "$b")" \
        "$(printf '%02x' "$c")" \
        "$(printf '%02x' "$d")" \
        value hex \
        "$(printf '%02x' "$((ifindex & 255))")" \
        "$(printf '%02x' "$(((ifindex >> 8) & 255))")" \
        "$(printf '%02x' "$(((ifindex >> 16) & 255))")" \
        "$(printf '%02x' "$(((ifindex >> 24) & 255))")"

    echo "Initialized local IP $ip on $iface (ifindex $ifindex)"
}

set_local_ip "10.0.1.1" "router-left"
set_local_ip "10.0.2.1" "router-right"

set_interface_mac() {
    local iface="$1"
    local ifindex
    local mac

    ifindex=$(ip -n labR -o link show dev "$iface" |
        awk -F: 'NR == 1 {
            gsub(/[[:space:]]/, "", $1)
            print $1
        }')

    mac=$(ip -n labR link show dev "$iface" |
        awk '/link\/ether/ {print $2; exit}')

    if [[ ! "$ifindex" =~ ^[0-9]+$ ||
          ! "$mac" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
        echo "ERROR: Invalid interface information for $iface" >&2
        return 1
    fi

    IFS=: read -r -a mac_bytes <<< "$mac"

    "$BPFTOOL" map update pinned "$MAP_DIR/interface_mac_map" \
        key hex \
        "$(printf '%02x' "$((ifindex & 255))")" \
        "$(printf '%02x' "$(((ifindex >> 8) & 255))")" \
        "$(printf '%02x' "$(((ifindex >> 16) & 255))")" \
        "$(printf '%02x' "$(((ifindex >> 24) & 255))")" \
        value hex "${mac_bytes[@]}"

    echo "Initialized interface $iface (ifindex $ifindex, MAC $mac)"
}

set_interface_mac "router-left"
set_interface_mac "router-right"

set_arp_entry() {
    local ip="$1"
    local namespace="$2"
    local iface="$3"
    local mac

    mac=$(ip -n "$namespace" link show dev "$iface" |
        awk '/link\/ether/ {print $2; exit}')

    if [[ ! "$mac" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
        echo "ERROR: Invalid MAC for $namespace/$iface" >&2
        return 1
    fi

    # Convert IPv4 address to four network-order bytes.
    IFS=. read -r a b c d <<< "$ip"

    # Convert MAC address to six bytes.
    IFS=: read -r -a mac_bytes <<< "$mac"

    "$BPFTOOL" map update pinned "$MAP_DIR/arp_cache" \
        key hex \
        "$(printf '%02x' "$a")" \
        "$(printf '%02x' "$b")" \
        "$(printf '%02x' "$c")" \
        "$(printf '%02x' "$d")" \
        value hex "${mac_bytes[@]}"

    echo "Initialized ARP entry $ip -> $mac"
}

set_arp_entry "10.0.1.2" "labA" "test-left"
set_arp_entry "10.0.2.2" "labB" "test-right"