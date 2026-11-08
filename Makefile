CC := cc
CLANG := clang

CFLAGS := -Wall -Wextra -Wpedantic -Iinclude
BPF_CFLAGS := -Wall -Wextra -O2 -g -target bpf \
              -I/usr/include/x86_64-linux-gnu -Iinclude

.PHONY: all load clean

all: xdp_pass.bpf.o route_loader arp_helper

xdp_pass.bpf.o: xdp_pass.bpf.c include/route_types.h
	$(CLANG) $(BPF_CFLAGS) -c $< -o $@

route_loader: route_loader.c include/route_types.h
	$(CC) $(CFLAGS) $< -o $@ -lbpf

arp_helper: arp_helper.c include/route_types.h
	$(CC) $(CFLAGS) $< -o $@ -lbpf

load: xdp_pass.bpf.o
	sudo bash load_xdp.sh

clean:
	rm -f xdp_pass.bpf.o route_loader arp_helper