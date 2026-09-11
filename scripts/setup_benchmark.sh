#!/usr/bin/env bash
# scripts/setup_benchmark.sh
# High-level setup for one benchmark configuration
# Calls low-level helpers — no hard-wired values
#
# Usage: sudo bash scripts/setup_benchmark.sh <config> <rule_count> <dst_port>
#
# Examples:
#   sudo bash scripts/setup_benchmark.sh b2 10 80
#   sudo bash scripts/setup_benchmark.sh b1 100 5500
#   sudo bash scripts/setup_benchmark.sh config_a 10 9900

set -euo pipefail

CONFIG=${1:-b2}
RULE_COUNT=${2:-10}
DST_PORT=${3:-80}

echo "========================================================"
echo " Setup: config=$CONFIG  rules=$RULE_COUNT  port=$DST_PORT"
echo "========================================================"

# Step 1 — Generate and apply rules
echo "[1/4] Generating $RULE_COUNT rules for $CONFIG..."
if [ "$CONFIG" = "config_a" ]; then
    python3 scripts/rule_generator.py $RULE_COUNT config_a --apply
else
    # For B1/B2 — apply iptables rules too so forwarding works
    python3 scripts/rule_generator.py $RULE_COUNT config_a --apply
fi

# Step 2 — Attach firewall program
echo "[2/4] Attaching $CONFIG firewall..."
sudo bash scripts/tc_attach.sh detach ens19 2>/dev/null || true

case "$CONFIG" in
    config_a)
        echo "  iptables rules already applied — no BPF attachment needed"
        ;;
    b2)
        sudo bash scripts/tc_attach.sh attach ens19 obj/firewall_b2.bpf.o tc
        ;;
    b1)
        sudo pkill b1_loader 2>/dev/null || true
        sleep 1
        sudo nohup ./obj/b1_loader ens19 > /tmp/b1_loader.log 2>&1 &
        sleep 3
        echo "  B1 loader running (nohup) — log at /tmp/b1_loader.log"
        ;;
    *)
        echo "ERROR: unknown config $CONFIG"
        exit 1
        ;;
esac

# Step 3 — Setup egress counter
echo "[3/4] Setting up BPF counter on ens20 egress for port $DST_PORT..."
sudo tc filter del dev ens20 egress 2>/dev/null || true
sudo tc qdisc add dev ens20 clsact 2>/dev/null || true
sudo tc filter add dev ens20 egress bpf \
    obj obj/pkt_counter_port.bpf.o sec tc direct-action
sudo bash scripts/set_counter_port.sh $DST_PORT

# Step 4 — Zero the counter
echo "[4/4] Zeroing counter..."
sudo bpftool map update name fwd_counter \
    key 0 0 0 0 value 0 0 0 0 0 0 0 0 2>/dev/null || true

echo ""
echo " Setup complete"
echo "  Config:   $CONFIG"
echo "  Rules:    $RULE_COUNT"
echo "  Port:     $DST_PORT"
echo "  Counter:  ready on ens20 egress"
echo ""
echo "Now run on xdp-sender:"
echo "  sudo bash scripts/bench_pktgen.sh $CONFIG $RULE_COUNT <match_pos> <verdict>"
