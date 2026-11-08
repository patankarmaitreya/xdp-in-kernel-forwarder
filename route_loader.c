#include <bpf/bpf.h>
#include <stdio.h>
#include <unistd.h>
#include <arpa/inet.h>

#include "route_types.h"

int main(void){
    int fd = bpf_obj_get("/sys/fs/bpf/xdp_maps/routing_table");

    if(fd < 0){
        perror("bpf_obj_get failed");
        return 1;
    }

    FILE *file = fopen("routes.conf", "r");
    if (file == NULL) {
        perror("Error opening file");
        close(fd);
        return 1;
    }

    char line[256];
    
    while (fgets(line, sizeof(line), file) != NULL) 
    {        
        __u32 prefixlen;
        char dst_ip[16];
        char nxt_hop_ip[16];
        __u32 out_ifindex;
        __u32 is_direct;

        int count = sscanf(line, "%15[^/]/%u %15s %u %u", dst_ip, &prefixlen, nxt_hop_ip, &out_ifindex, &is_direct);

        if (count != 5) {
            fprintf(stderr, "Invalid route: expected 5 fields, got %d\n", count);
            goto cleanup_error;
        }

        struct ipv4_route_key key = {0};
        struct ipv4_route_value value = {0};

        if(prefixlen > 32){
            printf("Invalid prefix length\n");
            goto cleanup_error;
        }
        key.prefixlen = prefixlen;

        if (inet_pton(AF_INET, dst_ip, key.addr) != 1) {
            fprintf(stderr, "Invalid destination IP: %s\n", dst_ip);
            goto cleanup_error;
        }
        
        if (inet_pton(AF_INET, nxt_hop_ip, &value.next_hop_ip) != 1) {
            fprintf(stderr, "Invalid next hop IP: %s\n", nxt_hop_ip);
            goto cleanup_error;
        }

        if (out_ifindex == 0) {
            fprintf(stderr, "Invalid outgoing interface index\n");
            goto cleanup_error;
        }
        value.out_ifindex = out_ifindex;

        if(is_direct != 0 && is_direct != 1){
            printf("Invalid direct flag\n");
            goto cleanup_error;
        }
        value.is_direct = is_direct;

        printf("Network: %s\n", dst_ip);
        printf("Prefix length: %u\n", prefixlen);
        printf("Next Hop: %s\n", nxt_hop_ip);
        printf("Interface index: %u\n", out_ifindex);
        printf("direct: %u\n", is_direct);

        int update = bpf_map_update_elem(fd, &key, &value, BPF_ANY);

        if(update < 0){
            perror("bpf_map_update_elem failed");
            goto cleanup_error;
        }
    }

    if (ferror(file)) {
        fprintf(stderr, "Error reading routes.conf\n");
        goto cleanup_error;
    }

    fclose(file);
    close(fd);
    return 0;

    cleanup_error:
        fclose(file);
        close(fd);
        return 1;
}
