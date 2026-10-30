#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>
#include <linux/ip.h>

#define IPV4_MF          0x2000
#define IPV4_OFFSET 0x1FFF

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

    return XDP_PASS;
}


char LICENSE[] SEC("license") = "GPL";