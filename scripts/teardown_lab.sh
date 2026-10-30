#!/usr/bin/env bash

set -e 

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run this script as root"
    exit 1
fi

if ip netns list | grep -Eq '^labA([[:space:]]|$)'; then
    ip netns del labA
    echo "Removed labA"
fi

if ip netns list | grep -Eq '^labB([[:space:]]|$)'; then
    ip netns del labB
    echo "Removed labB"
fi

echo "Lab teardown completed"