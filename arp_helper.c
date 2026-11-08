#include <stdio.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <linux/if_ether.h>

#include <linux/if_packet.h>
#include <net/if.h>
#include <linux/if_arp.h>

#include <bpf/bpf.h>
#include <string.h>
#include "route_types.h"

int main(void){

    int fd = -1;
    int fd_arp_cache = -1;
    int result = 1;

    fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ARP));

    if(fd < 0){
        perror("AF_Packet socket creation failed\n");
        return 1;
    }

    printf("AF_Packet socket file descriptor = %d\n", fd);

    unsigned int interface_idx = if_nametoindex("test-right");

    if(interface_idx == 0){
        perror("Failed to get interface index\n");
        goto cleanup;
    }

    struct sockaddr_ll addr= {0};
    addr.sll_family = AF_PACKET;
    addr.sll_protocol = htons(ETH_P_ARP);
    addr.sll_ifindex = interface_idx;

    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("Failed to bind ARP socket");
        goto cleanup;
    }

    printf("ARP socket bound to test-right\n");

    fd_arp_cache = bpf_obj_get("/run/bpf/xdp_maps/arp_cache");

    if(fd_arp_cache < 0){
        perror("bpf_obj_get failed");
        goto cleanup;
    }

    unsigned char buffer[2048];

    while(1)
    {
        ssize_t bytes_received = recv(fd, buffer, sizeof(buffer), 0);

        if(bytes_received < 0){
            perror("recv failed");
            goto cleanup;
        }

        printf("Number of bytes received = %zd\n", bytes_received);

        if((size_t)bytes_received < sizeof(struct ethhdr)){
            continue;
        }

        struct ethhdr *eth = (void *)buffer;

        __u16 proto = ntohs(eth->h_proto);

        printf("EtherType: 0x%x\n", proto);

        if(proto != ETH_P_ARP)
        {
            printf("Not a ARP packet\n");
            goto cleanup;
        }

        if((size_t)bytes_received < sizeof(struct ethhdr) + sizeof(struct arphdr)){
            fprintf(stderr, "Incomplete arp message\n");
            continue;
        }

        struct arphdr *arph = (void *)(eth + 1);

        printf("Hardware type: %u\n", ntohs(arph->ar_hrd));
        printf("Protocol type: 0x%x\n", ntohs(arph->ar_pro));
        printf("Hardware address length: %u\n", arph->ar_hln);
        printf("Protocol address length: %u\n", arph->ar_pln);
        printf("Operation: %u\n", ntohs(arph->ar_op));

        if((size_t)bytes_received < 42){
            fprintf(stderr, "Incomplete ip and mac addresses\n");
            continue;
        }

        if (ntohs(arph->ar_hrd) != ARPHRD_ETHER ||
        ntohs(arph->ar_pro) != ETH_P_IP ||
        arph->ar_hln != 6 ||
        arph->ar_pln != 4) 
        {
            fprintf(stderr, "Unsupported ARP format\n");
            continue;
        }

        if(ntohs(arph->ar_op) != ARPOP_REPLY){
            printf("Not a ARP reply packet\n");
            continue;
        }

        unsigned char *addr_ptr = (unsigned char *)(arph + 1);

        unsigned char *sender_mac = addr_ptr;
        unsigned char *sender_ip = addr_ptr + 6;

        unsigned char *target_mac = addr_ptr + 10;
        unsigned char *target_ip = addr_ptr + 16;

        printf("Sender MAC: %02x:%02x:%02x:%02x:%02x:%02x\n",
            sender_mac[0], sender_mac[1], sender_mac[2],
            sender_mac[3], sender_mac[4], sender_mac[5]);
        
        char src_ip_text[INET_ADDRSTRLEN];

        if (inet_ntop(AF_INET, sender_ip, src_ip_text, sizeof(src_ip_text)) == NULL) {
            perror("Failed to convert sender IP");
            goto cleanup;
        }

        printf("Sender IP: %s\n", src_ip_text);

        printf("Target MAC: %02x:%02x:%02x:%02x:%02x:%02x\n",
            target_mac[0], target_mac[1], target_mac[2],
            target_mac[3], target_mac[4], target_mac[5]);
        
        char trg_ip_text[INET_ADDRSTRLEN];

        if (inet_ntop(AF_INET, target_ip, trg_ip_text, sizeof(trg_ip_text)) == NULL) {
            perror("Failed to convert target IP");
            goto cleanup;
        }

        printf("Target IP: %s\n", trg_ip_text);

        struct arp_entry entry = {0};

        memcpy(entry.mac, sender_mac, sizeof(entry.mac));

        __u32 key = 0;
        memcpy(&key, sender_ip, sizeof(key));

        if (bpf_map_update_elem(fd_arp_cache, &key, &entry, BPF_ANY) < 0) {
            perror("Failed to update ARP cache");
            goto cleanup;
        }
        
        printf("ARP cache updated successfully\n");
    }
    
    cleanup:
        if (fd_arp_cache >= 0)
            close(fd_arp_cache);

        if (fd >= 0)
            close(fd);

        return result;
}
