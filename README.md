# eBPF/XDP In-Kernel Packet Forwarder

A Linux packet-forwarding project built using **eBPF and XDP**, aiming to implement high-performance IPv4 forwarding directly in the kernel.

The project explores packet parsing, routing, header manipulation, and XDP-based forwarding, with plans to benchmark performance against a userspace C++ router.

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