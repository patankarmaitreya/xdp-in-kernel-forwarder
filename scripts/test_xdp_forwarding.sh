#!/usr/bin/env bash
set -euo pipefail

BPFTOOL=/usr/lib/linux-tools-6.8.0-147/bpftool
ARP_MAP=/sys/fs/bpf/xdp_maps/arp_cache
STATS_MAP=/sys/fs/bpf/xdp_maps/route_stats

get_route_misses() {
    "$BPFTOOL" -j map lookup pinned "$STATS_MAP" \
        key hex 01 00 00 00 |
        python3 -c '
import json
import sys

data = json.load(sys.stdin)

# Use BTF-decoded integer values instead of raw bytes.
print(sum(cpu["value"] for cpu in data["formatted"]["values"]))
'
}

get_route_hits() {
    "$BPFTOOL" -j map lookup pinned "$STATS_MAP" \
        key hex 00 00 00 00 |
        python3 -c '
import json
import sys

data = json.load(sys.stdin)
print(sum(cpu["value"] for cpu in data["formatted"]["values"]))
'
}

echo "Checking test environment..."

# Ensure Linux forwarding is disabled.
forwarding=$(ip netns exec labR sysctl -n net.ipv4.ip_forward)

if [[ "$forwarding" != "0" ]]; then
    echo "FAIL: Linux IP forwarding is enabled"
    exit 1
fi

# Ensure both router interfaces have XDP attached.
for iface in router-left router-right; do
    if ! ip -n labR -d link show dev "$iface" | grep -q "prog/xdp id"; then
        echo "FAIL: XDP not attached to $iface"
        exit 1
    fi
done

echo "PASS: Test environment configured"

# Test 1: Normal forwarding should succeed.
echo "Test 1: Normal forwarding"

if ip netns exec labA ping -c 1 -W 1 10.0.2.2; then
    echo "PASS: Normal forwarding"
else
    echo "FAIL: Normal forwarding"
    exit 1
fi

# Test 2: TTL=1 should not reach the destination.
echo "Test 2: TTL expiration"

if ip netns exec labA ping -c 1 -W 1 -t 1 10.0.2.2; then
    echo "FAIL: TTL=1 packet unexpectedly reached labB"
    exit 1
else
    echo "PASS: TTL=1 packet was not delivered"
fi

# Test 3: Missing route
echo "Test 3: Missing route"

misses_before=$(get_route_misses)

if ip netns exec labA ping -c 1 -W 1 10.0.3.2; then
    echo "FAIL: Unexpected reply from unroutable destination"
    exit 1
fi

misses_after=$(get_route_misses)

if (( misses_after == misses_before + 1 )); then
    echo "PASS: Route-miss counter increased by 1"
else
    echo "FAIL: Expected one route miss"
    echo "Before: $misses_before, After: $misses_after"
    exit 1
fi

# Test 4: ARP cache miss
echo "Test 4: ARP cache miss"

# Restore the ARP entry even if the script fails or is interrupted.
restore_arp() {
    "$BPFTOOL" map update pinned "$ARP_MAP" \
        key hex 0a 00 02 02 \
        value hex ce e5 27 b9 cf d5
}

trap restore_arp EXIT

hits_before=$(get_route_hits)

# Temporarily remove labB's ARP entry.
"$BPFTOOL" map delete pinned "$ARP_MAP" \
    key hex 0a 00 02 02

if ip netns exec labA ping -c 1 -W 1 10.0.2.2; then
    echo "FAIL: Ping succeeded despite missing ARP entry"
    exit 1
else
    echo "PASS: Ping failed with missing ARP entry"
fi

hits_after=$(get_route_hits)

if (( hits_after == hits_before + 1 )); then
    echo "PASS: Route-hit counter increased by 1 during ARP miss"
else
    echo "FAIL: Expected one route hit during ARP miss"
    echo "Before: $hits_before, After: $hits_after"
    exit 1
fi

# Restore normal forwarding.
restore_arp
trap - EXIT

if ip netns exec labA ping -c 1 -W 1 10.0.2.2; then
    echo "PASS: Forwarding restored"
else
    echo "FAIL: Forwarding did not recover"
    exit 1
fi

# Test 5: ICMP burst forwarding
echo "Test 5: ICMP burst"

hits_before=$(get_route_hits)

ping_output=$(ip netns exec labA \
    ping -q -c 20 -i 0.05 -W 1 10.0.2.2) || {
    echo "$ping_output"
    echo "FAIL: ICMP burst"
    exit 1
}

echo "$ping_output"

hits_after=$(get_route_hits)

if (( hits_after == hits_before + 40 )); then
    echo "PASS: 40 route hits recorded for 20 successful pings"
else
    echo "FAIL: Unexpected route-hit count"
    echo "Before: $hits_before, After: $hits_after"
    exit 1
fi

if grep -qE '^20 packets transmitted, 20 received,' <<< "$ping_output"; then
    echo "PASS: All 20 ICMP packets received"
else
    echo "FAIL: Expected 20/20 ICMP replies"
    exit 1
fi

# Test 6: TCP forwarding
echo "Test 6: TCP forwarding"

tcp_dir=$(mktemp -d)
tcp_pid=""

cleanup_tcp() {
    if [[ -n "$tcp_pid" ]]; then
        kill "$tcp_pid" 2>/dev/null || true
        wait "$tcp_pid" 2>/dev/null || true
    fi
    rm -rf "$tcp_dir"
}

trap cleanup_tcp EXIT

# Start TCP server in labB.
ip netns exec labB python3 -u - "$tcp_dir/ready" \
    >"$tcp_dir/server.log" 2>&1 <<'PY' &
import socket
import sys

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("10.0.2.2", 9090))
    server.listen(1)
    server.settimeout(5)

    # Signal readiness only after listen() succeeds.
    open(sys.argv[1], "w").close()

    conn, addr = server.accept()
    with conn:
        data = conn.recv(1024)
        assert data == b"hello-xdp"
        conn.sendall(b"ACK:" + data)
PY

tcp_pid=$!

# Wait for the server's readiness signal, up to 5 seconds.
ready=0

for ((i = 0; i < 50; i++)); do
    if [[ -f "$tcp_dir/ready" ]]; then
        ready=1
        break
    fi

    if ! kill -0 "$tcp_pid" 2>/dev/null; then
        break
    fi

    sleep 0.1
done

if (( ready == 0 )); then
    cat "$tcp_dir/server.log"
    echo "FAIL: TCP server did not become ready"
    exit 1
fi

# Connect to the server from labA.
ip netns exec labA python3 - <<'PY'
import socket

with socket.create_connection(("10.0.2.2", 9090), timeout=5) as client:
    client.sendall(b"hello-xdp")
    response = client.recv(1024)

    assert response == b"ACK:hello-xdp", response

print("PASS: TCP data exchange")
PY

# Verify the server exited successfully.
if ! wait "$tcp_pid"; then
    cat "$tcp_dir/server.log"
    echo "FAIL: TCP server error"
    exit 1
fi

tcp_pid=""
cleanup_tcp
trap - EXIT

echo "PASS: TCP forwarding"

echo "All tests passed."