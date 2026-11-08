# eBPF/XDP In-Kernel Packet Forwarder

A Linux packet-forwarding project built using **eBPF and XDP**, aiming to implement high-performance IPv4 forwarding directly in the kernel.

The project explores packet parsing, routing, header manipulation, and XDP-based forwarding, with plans to benchmark performance against a userspace C++ router.

## Commands

**Compile**

- clang -Wall -Wextra -O2 -g -target bpf \
    -I/usr/include/x86_64-linux-gnu \
    -Iinclude \
    -c xdp_pass.bpf.c \
    -o xdp_pass.bpf.o

**load Program**

- sudo /usr/lib/linux-tools-6.8.0-147/bpftool \
    prog load xdp_pass.bpf.o /sys/fs/bpf/xdp_eth_parse type xdp

## Current Progress

**Sprint 1 — Completed**

- Set up Linux network namespaces and virtual Ethernet (veth) interfaces.
- Configured IPv4 addresses, routing, and ARP connectivity.
- Inspected network traffic using `tcpdump`.
- Implemented a basic `XDP_PASS` program in C.
- Compiled, loaded, and attached the XDP program using Clang and `bpftool`.
- Created Bash scripts for automated network setup, validation, and teardown.

## Next Steps

- Verifier-safe Ethernet and IPv4 packet parsing.
- Routing lookups using BPF maps.
- TTL, checksum, and Ethernet header modifications.
- Packet forwarding using `XDP_REDIRECT`.
- Performance benchmarking.

**Status:** In development. Currently supports XDP packet reception with `XDP_PASS`; packet forwarding is not yet implemented.