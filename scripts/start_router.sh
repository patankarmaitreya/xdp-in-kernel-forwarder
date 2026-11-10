#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root"
    exit 1
fi

# Ensure commands run from the project root.
cd "$(dirname "$0")/.."

PROG_PIN=/sys/fs/bpf/xdp_ipv4_mac_lookup
MAP_DIR=/sys/fs/bpf/xdp_maps

# Check that the project has been compiled.
for file in xdp_pass.bpf.o route_loader; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Missing $file. Run 'make all' first."
        exit 1
    fi
done

# Require a clean network topology.
for ns in labA labB labR; do
    if ip netns list | grep -Eq "^${ns}([[:space:]]|$)"; then
        echo "ERROR: Namespace $ns already exists."
        echo "Clean up the previous lab before starting."
        exit 1
    fi
done

# Require clean BPF pins to avoid reusing stale interface data.
if [[ -e "$PROG_PIN" ]]; then
    echo "ERROR: Existing XDP program pin found."
    exit 1
fi

for map in \
    routing_table route_stats local_ip_map \
    arp_cache interface_mac_map xdp_pass_rodata
do
    if [[ -e "$MAP_DIR/$map" ]]; then
        echo "ERROR: Existing BPF map pin found: $map"
        echo "Run the BPF cleanup script after tearing down the lab."
        exit 1
    fi
done

echo "Step 1: Creating network topology"
bash scripts/setup_router_lab.sh

echo "Step 2: Generating routing configuration"
bash scripts/generate_routes.sh

echo "Step 3: Loading XDP program and creating maps"
bash load_xdp.sh

echo "Step 4: Initializing BPF maps"
bash scripts/init_router_maps.sh

echo "Step 5: Disabling Linux IP forwarding"
ip netns exec labR sysctl -w net.ipv4.ip_forward=0

echo "Step 6: Attaching XDP to router interfaces"

for iface in router-left router-right; do
    nsenter --net=/run/netns/labR -- \
        ip link set dev "$iface" xdpgeneric \
        pinned "$PROG_PIN"

    echo "Attached XDP to $iface"
done

echo "Router initialization completed successfully"