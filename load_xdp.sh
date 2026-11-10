#!/usr/bin/env bash
set -euo pipefail

BPFTOOL=/usr/lib/linux-tools-6.8.0-147/bpftool
MAP_DIR=/sys/fs/bpf/xdp_maps
PROG_PIN=/sys/fs/bpf/xdp_ipv4_mac_lookup
TEMP_PROG_PIN="${PROG_PIN}_candidate_$$"

MAP_NAMES=(
    routing_table
    route_stats
    local_ip_map
    arp_cache
    interface_mac_map
)

existing_count=0

for map in "${MAP_NAMES[@]}"; do
    if [[ -e "$MAP_DIR/$map" ]]; then
        existing_count=$((existing_count + 1))
    fi
done

echo "Found $existing_count of ${#MAP_NAMES[@]} required BPF maps"

if (( existing_count != 0 &&
      existing_count != ${#MAP_NAMES[@]} )); then
    echo "ERROR: Partial BPF map initialization detected" >&2
    echo "Found $existing_count of ${#MAP_NAMES[@]} required maps" >&2
    exit 1
fi

# Ensure the map pin directory exists.
mkdir -p "$MAP_DIR"

if (( existing_count == 0 )); then
    echo "Fresh installation: creating and pinning BPF maps"

    cmd=(
        "$BPFTOOL" prog load xdp_pass.bpf.o "$TEMP_PROG_PIN"
        type xdp
        pinmaps "$MAP_DIR"
    )
else
    echo "Existing installation: reusing pinned BPF maps"

    cmd=(
        "$BPFTOOL" prog load xdp_pass.bpf.o "$TEMP_PROG_PIN"
        type xdp
    )

    for map in "${MAP_NAMES[@]}"; do
        cmd+=(
            map name "$map"
            pinned "$MAP_DIR/$map"
        )
    done
fi

if [[ -e "$TEMP_PROG_PIN" ]]; then
    echo "ERROR: Temporary program pin already exists" >&2
    exit 1
fi

trap 'rm -f "$TEMP_PROG_PIN"' EXIT

# Load and validate the candidate before replacing the current pin.
"${cmd[@]}"
"$BPFTOOL" prog show pinned "$TEMP_PROG_PIN"

# Publish the successfully loaded program.
mv -f -- "$TEMP_PROG_PIN" "$PROG_PIN"

echo "XDP program loaded successfully"
"$BPFTOOL" prog show pinned "$PROG_PIN"