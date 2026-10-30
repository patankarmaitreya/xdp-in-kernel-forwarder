#!/usr/bin/env bash

set -e

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root"
    exit 1
fi

if ip netns list | grep -Eq '^labA([[:space:]]|$)'; then
    echo "ERROR: labA already exists"
    exit 1
fi

if ip netns list | grep -Eq '^labB([[:space:]]|$)'; then
    echo "ERROR: labB already exists"
    exit 1
fi

echo "Preflight checks passed"

ip netns add labA
ip netns add labB

echo "Namespaces created"

ip link add test-left type veth peer name test-right

ip link set test-left netns labA
ip link set test-right netns labB

echo "Veth pair successfully configured"

ip -n labA addr add 10.0.0.1/24 dev test-left
ip -n labB addr add 10.0.0.2/24 dev test-right

ip -n labA link set dev lo up
ip -n labA link set dev test-left up
ip -n labB link set dev lo up
ip -n labB link set dev test-right up

echo "Lab network configuration completed"