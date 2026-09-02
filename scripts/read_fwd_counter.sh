#!/usr/bin/env bash
# scripts/read_fwd_counter.sh
# Reads and sums per-CPU fwd_counter from pkt_counter_port BPF program
# Usage: sudo bash scripts/read_fwd_counter.sh

TOTAL=$(sudo bpftool map dump name fwd_counter 2>/dev/null | \
    grep '"value"' | \
    grep -oP '\d+' | \
    python3 -c "import sys; print(sum(int(x) for x in sys.stdin))")

echo "Forwarded packets: $TOTAL"
echo $TOTAL
