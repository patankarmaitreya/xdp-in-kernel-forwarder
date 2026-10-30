#!/usr/bin/env bash

if ip netns list | grep -Eq '^labA([[:space:]]|$)' >/dev/null 2>&1; then
    echo "PASS: namespace labA exists"
else
    echo "FAIL: namespace labA missing"
    exit 1
fi

if ip netns list | grep -Eq '^labB([[:space:]]|$)' >/dev/null 2>&1; then
    echo "PASS: namespace labB exists"
else
    echo "FAIL: namespace labB missing"
    exit 1
fi

if ip netns exec labA ip link show dev test-left >/dev/null 2>&1; then
    echo "PASS: test-left interface exists"
else
    echo "FAIL: test-left interface missing"
    exit 1
fi

if ip netns exec labB ip link show dev test-right >/dev/null 2>&1; then
    echo "PASS: test-right interface exists"
else
    echo "FAIL: test-right interface missing"
    exit 1
fi

if ip -n labA link show dev test-left | grep -q 'state UP'; then
    echo "PASS: test-left is operational"
else
    echo "FAIL: test-left is not operational"
    exit 1
fi

if ip -n labB link show dev test-right | grep -q 'state UP'; then
    echo "PASS: test-right is operational"
else
    echo "FAIL: test-right is not operational"
    exit 1
fi

if ip -n labA route show 10.0.0.0/24 | grep -q 'dev test-left'; then
    echo "PASS: labA has the expected route"
else
    echo "FAIL: labA route missing or incorrect"
    exit 1
fi

if ip -n labB route show 10.0.0.0/24 | grep -q 'dev test-right'; then
    echo "PASS: labB has the expected route"
else
    echo "FAIL: labB route missing or incorrect"
    exit 1
fi

if ip netns exec labA ping -c 1 -W 1 10.0.0.2 >/dev/null 2>&1; then
    echo "PASS: labA can reach labB"
else
    echo "FAIL: labA cannot reach labB"
    exit 1
fi

if ip netns exec labB ping -c 1 -W 1 10.0.0.1 >/dev/null 2>&1; then
    echo "PASS: labB can reach labA"
else
    echo "FAIL: labB cannot reach labA"
    exit 1
fi

echo "PASS: All configured checks completed"