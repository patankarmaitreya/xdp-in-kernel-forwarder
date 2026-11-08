#pragma once

#include <linux/types.h>

#define IPV4_MF     0x2000
#define IPV4_OFFSET 0x1FFF

#define ROUTE_HIT  0
#define ROUTE_MISS 1

struct ipv4_route_key{
    __u32 prefixlen; // LPM trie requires a 32-bit prefix length
    __u8 addr[4];
};

struct ipv4_route_value{
    __u32 next_hop_ip;
    __u32 out_ifindex;
    __u8 is_direct;
};

struct arp_entry {
    __u8 mac[6];
};
