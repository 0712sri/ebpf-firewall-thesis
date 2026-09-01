#!/usr/bin/env bash
# scripts/set_counter_port.sh
# Sets the target port in pkt_counter_port BPF map
# Usage: sudo bash scripts/set_counter_port.sh <port>

PORT=${1:-80}
echo "Setting counter port to $PORT"
sudo bpftool map update name target_port_map key 0 0 0 0 value $(printf '%d %d' $((PORT & 0xFF)) $((PORT >> 8))) 2>/dev/null || \
sudo bpftool map update name target_port_map key 0 0 0 0 value $((PORT >> 8)) $((PORT & 0xFF))
echo "✓ Counter now tracking UDP dst port $PORT"