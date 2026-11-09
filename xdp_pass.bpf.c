#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include <linux/ip.h>

#include "route_types.h"

struct {
    __uint(type, BPF_MAP_TYPE_LPM_TRIE);
    __type(key, struct ipv4_route_key);
    __type(value, struct ipv4_route_value);
    __uint(max_entries, 128);
    __uint(map_flags, BPF_F_NO_PREALLOC);
} routing_table SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __type(key, __u32);
    __type(value, __u64);
    __uint(max_entries, 2);
} route_stats SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __type(key, __u32);
    __type(value, __u32);
    __uint(max_entries, 64);
} local_ip_map SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __type(key, __u32);
    __type(value, struct arp_entry);
    __uint(max_entries, 256);
} arp_cache SEC(".maps");

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __type(key, __u32);
    __type(value, struct arp_entry);
    __uint(max_entries, 64);
} interface_mac_map SEC(".maps");

static __always_inline __u16 update_checksum(
    __u16 old_checksum,
    __u16 old_word,
    __u16 new_word)
{
    __u32 sum = (~old_checksum & 0xFFFF)
          + (~old_word & 0xFFFF)
          + new_word;
        
    sum = (sum & 0xFFFF) + (sum >> 16);
    sum = (sum & 0xFFFF) + (sum >> 16);

    return (__u16)(~sum);
}

SEC("xdp")
int xdp_pass(struct xdp_md *ctx)
{
    void *data = (void *)(long)ctx->data;
    void *data_end = (void *)(long)ctx->data_end;

    struct ethhdr *eth = data;

    if((void *)(eth + 1) > data_end){
        return XDP_PASS;        
    }

    __u16 proto = bpf_ntohs(eth->h_proto);

    if(proto != ETH_P_IP){
        return XDP_PASS;
    }

    bpf_printk("IPv4 EtherType: 0x%x", proto);

    struct iphdr *iph = (void *)(eth + 1);

    if((void *)(iph + 1) > data_end){
        return XDP_PASS;
    }

    if(iph->ihl < 5 || iph->version != 4){
        return XDP_PASS;
    }

    __u8 ihl_bytes = iph->ihl * 4;

    if((void *)((char *)iph + ihl_bytes) > data_end){
        return XDP_PASS;        
    }

    bpf_printk("IPv4 ihl: %u", iph->ihl);
    bpf_printk("IPv4 version: %u", iph->version);

    __u8 ttl = iph->ttl;    
    __u8 protocol = iph->protocol;    

    __u32 src_ip = bpf_ntohl(iph->saddr);
    __u32 dst_ip = bpf_ntohl(iph->daddr);

    __u16 tot_len = bpf_ntohs(iph->tot_len);

    if(tot_len < ihl_bytes || (void *)((char *)iph + tot_len) > data_end){
        return XDP_PASS;
    }

    __u16 frag = bpf_ntohs(iph->frag_off);

    if((frag & IPV4_MF) != 0 || (frag & IPV4_OFFSET) != 0){
        return XDP_PASS;
    }

    bpf_printk("IPv4 ttl: %u", ttl);
    bpf_printk("IPv4 protocol: %u", protocol);

    bpf_printk("IPv4 source ip: %x", src_ip);
    bpf_printk("IPv4 destination ip: %x", dst_ip);

    bpf_printk("IPv4 total length: %u", tot_len);

    bpf_printk("IPv4 unfragmented packet");

    __u32 local_ip = iph->daddr;

    __u32 *local_ifindex = bpf_map_lookup_elem(&local_ip_map, &local_ip);

    if(local_ifindex != NULL){
        return XDP_PASS;
    }

    struct ipv4_route_key key = {0};
    key.prefixlen = 32;
    __builtin_memcpy(key.addr, &iph->daddr, sizeof(key.addr));

    struct ipv4_route_value *route = bpf_map_lookup_elem(&routing_table, &key);

    if(route == NULL){
        bpf_printk("Route is missing");

        __u32 stat_key = ROUTE_MISS;
        __u64 *stat = bpf_map_lookup_elem(&route_stats, &stat_key);

        if(stat != NULL){
            *stat += 1;
        }
    }
    else{
        bpf_printk("Route hit, outgoing interfae is %u", route->out_ifindex);

        __u32 stat_key = ROUTE_HIT;
        __u64 *stat = bpf_map_lookup_elem(&route_stats, &stat_key);
        if(stat != NULL){
            *stat += 1;
        }

        if(ttl <= 1){
            return XDP_PASS;
        }

        __u16 old_word = (ttl << 8) | protocol;
        
        ttl -= 1;
        __u16 new_word = (ttl << 8) | protocol;

        __u16 old_checksum = bpf_ntohs(iph->check);

        __u16 new_checksum = update_checksum(old_checksum, old_word, new_word);

        bpf_printk("TTL: %u -> %u", iph->ttl, ttl);
        bpf_printk("Checksum: 0x%x -> 0x%x",old_checksum, new_checksum);

        __u32 arp_lookup_ip;

        if (route->is_direct == 1) {
            arp_lookup_ip = iph->daddr;
        } else {
            arp_lookup_ip = route->next_hop_ip;
        }

        struct arp_entry  *dst_arp_val = bpf_map_lookup_elem(&arp_cache, &arp_lookup_ip);

        if(dst_arp_val != NULL){
            bpf_printk("ARP cache hit");
        }
        else{
            bpf_printk("ARP cache miss");   
            return XDP_PASS;
        }
        
        __u32 out_ifindex = route->out_ifindex; 
        struct arp_entry  *src_arp_val = bpf_map_lookup_elem(&interface_mac_map, &out_ifindex);
        if(src_arp_val != NULL){
            bpf_printk("Interface MAC found");
        }
        else{
            bpf_printk("Interface MAC missing");   
            return XDP_PASS;
        }

        iph->ttl = ttl;
        iph->check = bpf_htons(new_checksum);

        __builtin_memcpy(eth->h_source, src_arp_val->mac, ETH_ALEN);
        __builtin_memcpy(eth->h_dest, dst_arp_val->mac, ETH_ALEN);

        return bpf_redirect(route->out_ifindex, 0);
    }
    return XDP_PASS;
}


char LICENSE[] SEC("license") = "GPL";