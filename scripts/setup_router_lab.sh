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

if ip netns list | grep -Eq '^labR([[:space:]]|$)'; then
    echo "ERROR: labR already exists"
    exit 1
fi

echo "Preflight checks passed"

ip netns add labA
ip netns add labB
ip netns add labR

echo "Namespaces created"

ip link add test-left type veth peer name router-left
ip link add router-right type veth peer name test-right

ip link set test-left netns labA
ip link set test-right netns labB
ip link set router-left netns labR
ip link set router-right netns labR

echo "Veth pair successfully configured"

ip -n labA addr add 10.0.1.2/24 dev test-left
ip -n labB addr add 10.0.2.2/24 dev test-right
ip -n labR addr add 10.0.1.1/24 dev router-left
ip -n labR addr add 10.0.2.1/24 dev router-right

ip -n labA link set dev lo up
ip -n labA link set dev test-left up

ip -n labB link set dev lo up
ip -n labB link set dev test-right up

ip -n labR link set dev lo up
ip -n labR link set dev router-left up
ip -n labR link set dev router-right up



ip -n labA route add default via 10.0.1.1
ip -n labB route add default via 10.0.2.1