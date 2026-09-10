#!/usr/bin/env bash
# Outputs single integer — total forwarded packets
sudo bpftool map dump name fwd_counter 2>/dev/null | \
    grep '"value"' | \
    grep -oP '\d+' | \
    python3 -c "import sys; print(sum(int(x) for x in sys.stdin))"
