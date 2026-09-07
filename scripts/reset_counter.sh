#!/usr/bin/env bash
# scripts/reset_counter.sh
# Resets BPF egress counter between runs
# Usage: sudo bash scripts/reset_counter.sh <dst_port>

PORT=${1:-80}
sudo tc filter del dev ens20 egress 2>/dev/null || true
sudo tc filter add dev ens20 egress bpf \
    obj obj/pkt_counter_port.bpf.o sec tc direct-action
sudo bash scripts/set_counter_port.sh $PORT
sudo bpftool map update name fwd_counter \
    key 0 0 0 0 value 0 0 0 0 0 0 0 0 2>/dev/null || true
echo " Counter reset for port $PORT"
sudo bpftool map dump name fwd_counter | grep value
