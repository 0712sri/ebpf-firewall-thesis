#!/usr/bin/env bash
# scripts/run_benchmark.sh
# Laptop-side benchmark orchestrator
# Controls xdp-sender and xdp-firewall independently via SSH
# No VM-to-VM SSH — laptop is the controller
#
# Usage:
#   bash scripts/run_benchmark.sh <config> <rule_count> <match_pos> <verdict>

set -euo pipefail

CONFIG=${1:-b2}
RULE_COUNT=${2:-10}
MATCH_POS=${3:-best}
VERDICT=${4:-accept}

SENDER="ubuntu@10.8.50.179"
FIREWALL="ubuntu@10.8.50.175"
SENDER_REPO="/home/ubuntu/ebpf-firewall-thesis"
FIREWALL_REPO="/home/ubuntu/ebpf-firewall-thesis"
RESULTS_FILE="bench/pktgen_results.csv"

# Read port map from generated file
PORTMAP="bench/portmap_${RULE_COUNT}.txt"
if [ ! -f "$PORTMAP" ]; then
    echo "ERROR: port map not found — run: python3 scripts/rule_generator.py $RULE_COUNT config_a"
    exit 1
fi
source "$PORTMAP"

case "$MATCH_POS" in
    best)   DST_PORT=$BEST_PORT   ;;
    middle) DST_PORT=$MIDDLE_PORT ;;
    worst)  DST_PORT=$WORST_PORT  ;;
    miss)   DST_PORT=$MISS_PORT   ;;
    *) echo "ERROR: match_pos must be best|middle|worst|miss"; exit 1 ;;
esac

# Test config — change for full run
PACKET_SIZES=(64)
RATES=(10000)
REPETITIONS=1
DURATION_S=10

if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,config,rule_count,match_pos,dst_port,expected_verdict,pkt_size_bytes,target_pps,offered_pkts,pktgen_errors,pktgen_achieved_pps,pktgen_duration_us,forwarded_pkts,forwarded_loss_pct,repetition" > "$RESULTS_FILE"
fi
#!/usr/bin/env bash
# scripts/run_benchmark.sh
# Laptop-side benchmark orchestrator
# Controls xdp-sender and xdp-firewall independently via SSH
# No VM-to-VM SSH — laptop is the controller
#
# Usage:
#   bash scripts/run_benchmark.sh <config> <rule_count> <match_pos> <verdict>

set -euo pipefail

CONFIG=${1:-b2}
RULE_COUNT=${2:-10}
MATCH_POS=${3:-best}
VERDICT=${4:-accept}

SENDER="ubuntu@10.8.50.179"
FIREWALL="ubuntu@10.8.50.175"
SENDER_REPO="/home/ubuntu/ebpf-firewall-thesis"
FIREWALL_REPO="/home/ubuntu/ebpf-firewall-thesis"
RESULTS_FILE="bench/pktgen_results.csv"
SSH_OPTS="-o StrictHostKeyChecking=no -o ProxyJump=bastion"

# Read port map from generated file
PORTMAP="bench/portmap_${RULE_COUNT}.txt"
if [ ! -f "$PORTMAP" ]; then
    echo "ERROR: port map not found — run: python3 scripts/rule_generator.py $RULE_COUNT config_a"
    exit 1
fi
source "$PORTMAP"

case "$MATCH_POS" in
    best)   DST_PORT=$BEST_PORT   ;;
    middle) DST_PORT=$MIDDLE_PORT ;;
    worst)  DST_PORT=$WORST_PORT  ;;
    miss)   DST_PORT=$MISS_PORT   ;;
    *) echo "ERROR: match_pos must be best|middle|worst|miss"; exit 1 ;;
esac

# Test config — change for full run
PACKET_SIZES=(64)
RATES=(10000)
REPETITIONS=1
DURATION_S=10

if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,config,rule_count,match_pos,dst_port,expected_verdict,pkt_size_bytes,target_pps,offered_pkts,pktgen_errors,pktgen_achieved_pps,pktgen_duration_us,forwarded_pkts,forwarded_loss_pct,repetition" > "$RESULTS_FILE"
fi

echo "========================================================"
echo " Benchmark Orchestrator — laptop controls both VMs"
echo "========================================================"
echo " Config:    $CONFIG  |  Rules: $RULE_COUNT"
echo " Match pos: $MATCH_POS (port=$DST_PORT)  |  Verdict: $VERDICT"
echo " Sizes:     ${PACKET_SIZES[*]} bytes"
echo " Rates:     ${RATES[*]} pps"
echo " Duration:  ${DURATION_S}s per trial  |  Reps: $REPETITIONS"
echo "========================================================"

# Setup firewall once
echo ""
echo "[setup] Configuring xdp-firewall..."
ssh $SSH_OPTS "$FIREWALL" \
    "cd $FIREWALL_REPO && sudo bash scripts/setup_benchmark.sh $CONFIG $RULE_COUNT $DST_PORT"
echo "[setup] xdp-firewall ready"

# Run trials
for PKT_SIZE in "${PACKET_SIZES[@]}"; do
    for PPS in "${RATES[@]}"; do

        NUM_PKTS=$(( PPS * DURATION_S ))

        for REP in $(seq 1 $REPETITIONS); do

            echo ""
            echo "--- Size=${PKT_SIZE}B  Rate=${PPS}pps  Rep=${REP}/${REPETITIONS} ---"

            # Reset counter on firewall
            ssh $SSH_OPTS "$FIREWALL" \
                "cd $FIREWALL_REPO && sudo bash scripts/reset_counter.sh $DST_PORT"

            # Run pktgen on sender
            ssh $SSH_OPTS "$SENDER" \
                "cd $SENDER_REPO && sudo bash scripts/pktgen_sender.sh $PPS $PKT_SIZE $NUM_PKTS $DST_PORT"

            # Read counter from firewall
            FORWARDED=$(ssh $SSH_OPTS "$FIREWALL" \
                "cd $FIREWALL_REPO && sudo bash scripts/read_fwd_counter.sh")

            # Parse pktgen results from sender
            RESULT=$(ssh $SSH_OPTS "$SENDER" \
                "sudo cat /proc/net/pktgen/eth1")
            OFFERED=$(echo "$RESULT" | grep "pkts-sofar" | grep -oP '\d+' | head -1)
            PKTGEN_ERRORS=$(echo "$RESULT" | grep "errors:" | tail -1 | grep -oP 'errors: \d+' | grep -oP '\d+' || echo "0")
            ACHIEVED_PPS=$(echo "$RESULT" | grep -oP '\d+pps' | head -1 | grep -oP '\d+' || echo "0")
            DURATION=$(echo "$RESULT" | grep "Result:" | grep -oP '\d+(?=\()' | head -1 || echo "0")

            # Calculate loss
            if [ "$VERDICT" = "accept" ] && [ "${OFFERED:-0}" -gt 0 ]; then
                LOSS_PCT=$(python3 -c "
offered=int('${OFFERED:-0}')
fwd=int('${FORWARDED:-0}')
lost=offered-fwd
pct=(lost/offered)*100 if offered>0 else 0
print(f'{pct:.4f}')
")
            else
                LOSS_PCT="N/A"
            fi

            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            echo "${TIMESTAMP},${CONFIG},${RULE_COUNT},${MATCH_POS},${DST_PORT},${VERDICT},${PKT_SIZE},${PPS},${OFFERED:-0},${PKTGEN_ERRORS:-0},${ACHIEVED_PPS:-0},${DURATION:-0},${FORWARDED},${LOSS_PCT},${REP}" >> "$RESULTS_FILE"

            echo "  Offered: ${OFFERED:-0}  Forwarded: $FORWARDED  Loss: $LOSS_PCT"
            sleep 1
        done
    done
done

echo ""
echo "=== Done — results in $RESULTS_FILE ==="