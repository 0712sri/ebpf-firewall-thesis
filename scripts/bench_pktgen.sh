#!/usr/bin/env bash
# scripts/bench_pktgen.sh
# Packet-processing benchmark informed by Turull et al. (2016) and RFC 2544.
#
# Measures per trial:
#   - Offered packets (pktgen pkts-sofar)
#   - Forwarded packets (BPF counter on ens20 egress — benchmark port only)
#   - Forwarded loss % = (offered - forwarded) / offered  [ACCEPT tests only]
#   - pktgen achieved PPS
#   - pktgen run duration (generator elapsed time)
#   - pktgen errors
#
# Run on: xdp-sender
# Requires: pkt_counter_port.bpf.o attached to ens20 egress on xdp-firewall
#
# Usage:
#   sudo bash scripts/bench_pktgen.sh <config> <rule_count> <match_pos> <verdict>
#
#   match_pos: best | middle | worst | miss
#   verdict:   accept | drop
#
# Examples:
#   sudo bash scripts/bench_pktgen.sh config_a 10 best accept
#   sudo bash scripts/bench_pktgen.sh b2 100 worst accept
#   sudo bash scripts/bench_pktgen.sh b2 10 miss drop

set -euo pipefail

CONFIG=${1:-unknown}
RULE_COUNT=${2:-10}
MATCH_POS=${3:-best}
VERDICT=${4:-accept}
FIREWALL_HOST="xdp-firewall"
RESULTS_FILE="bench/pktgen_results.csv"

# Port based on match position — must match rule_generator.py output
case "$MATCH_POS" in
    best)   DST_PORT=80    ;;
    middle) DST_PORT=5500  ;;
    worst)  DST_PORT=9900  ;;
    miss)   DST_PORT=9999  ;;
    *) echo "ERROR: match_pos must be best|middle|worst|miss"; exit 1 ;;
esac

# Packet sizes per RFC 2544
PACKET_SIZES=(64 128 256 512 1024 1518)

# Offered rates (pps) — sweep from low to above NIC ceiling
RATES=(1000 5000 10000 15000 20000 25000 30000 35000 40000)

# Repetitions per configuration
REPETITIONS=3

# Duration target: 10 seconds per trial
# Packet count = rate × 10
DURATION_S=10

# Write CSV header only if file does not exist
if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,config,rule_count,match_pos,dst_port,expected_verdict,pkt_size_bytes,target_pps,offered_pkts,pktgen_errors,pktgen_achieved_pps,pktgen_duration_us,forwarded_pkts,forwarded_loss_pct,repetition" > "$RESULTS_FILE"
fi

echo "========================================================"
echo " Firewall Benchmark — Turull et al. 2016 / RFC 2544"
echo "========================================================"
echo " Config:    $CONFIG  |  Rules: $RULE_COUNT"
echo " Match pos: $MATCH_POS (port=$DST_PORT)  |  Verdict: $VERDICT"
echo " Sizes:     ${PACKET_SIZES[*]} bytes"
echo " Rates:     ${RATES[*]} pps"
echo " Duration:  ${DURATION_S}s per trial  |  Reps: $REPETITIONS"
echo "========================================================"

# Setup BPF counter on firewall for this port
echo "Setting up BPF counter on xdp-firewall ens20 for port $DST_PORT..."
ssh "$FIREWALL_HOST" "
    sudo tc filter del dev ens20 egress 2>/dev/null || true
    sudo tc filter add dev ens20 egress bpf obj ~/ebpf-firewall-thesis/obj/pkt_counter_port.bpf.o sec tc direct-action
    sudo bash ~/ebpf-firewall-thesis/scripts/set_counter_port.sh $DST_PORT
"
echo "✓ Counter ready"

sudo modprobe pktgen 2>/dev/null || true

for PKT_SIZE in "${PACKET_SIZES[@]}"; do
    for PPS in "${RATES[@]}"; do

        # Fixed 10-second duration — packet count scales with rate
        NUM_PKTS=$(( PPS * DURATION_S ))

        for REP in $(seq 1 $REPETITIONS); do

            echo ""
            echo "--- Config=$CONFIG  Size=${PKT_SIZE}B  Rate=${PPS}pps  Rep=${REP}/${REPETITIONS}  Pkts=$NUM_PKTS ---"

            # Reset BPF counter by reattaching
            ssh "$FIREWALL_HOST" "
                sudo tc filter del dev ens20 egress 2>/dev/null || true
                sudo tc filter add dev ens20 egress bpf obj ~/ebpf-firewall-thesis/obj/pkt_counter_port.bpf.o sec tc direct-action
                sudo bash ~/ebpf-firewall-thesis/scripts/set_counter_port.sh $DST_PORT
            " 2>/dev/null

            sleep 0.5  # let counter settle

            # Run pktgen
            sudo bash scripts/pktgen_sender.sh $PPS $PKT_SIZE $NUM_PKTS $DST_PORT

            # Read forwarded count from BPF counter
            FORWARDED=$(ssh "$FIREWALL_HOST" \
                "sudo bash ~/ebpf-firewall-thesis/scripts/read_fwd_counter.sh" \
                | tail -1 | tr -d ' \n')

            # Parse pktgen results
            RESULT=$(sudo cat /proc/net/pktgen/eth1)
            OFFERED=$(echo "$RESULT" | grep "pkts-sofar" | grep -oP '\d+' | head -1)
            PKTGEN_ERRORS=$(echo "$RESULT" | grep "errors:" | tail -1 | grep -oP 'errors: \d+' | grep -oP '\d+' || echo "0")
            ACHIEVED_PPS=$(echo "$RESULT" | grep -oP '\d+pps' | head -1 | grep -oP '\d+' || echo "0")
            DURATION=$(echo "$RESULT" | grep "Result:" | grep -oP '\d+(?=\()' | head -1 || echo "0")

            # Calculate loss — only meaningful for ACCEPT tests
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

            # Write to CSV
            echo "${TIMESTAMP},${CONFIG},${RULE_COUNT},${MATCH_POS},${DST_PORT},${VERDICT},${PKT_SIZE},${PPS},${OFFERED:-0},${PKTGEN_ERRORS:-0},${ACHIEVED_PPS:-0},${DURATION:-0},${FORWARDED:-0},${LOSS_PCT},${REP}" >> "$RESULTS_FILE"

            echo "  Offered:   ${OFFERED:-0} pkts"
            echo "  Forwarded: ${FORWARDED:-0} pkts"
            echo "  Loss:      ${LOSS_PCT}"
            echo "  PPS:       ${ACHIEVED_PPS:-0}"
            echo "  Duration:  ${DURATION:-0} us (generator elapsed)"
            echo "  Errors:    ${PKTGEN_ERRORS:-0}"

            sleep 2
        done
    done
done

echo ""
echo "=== Benchmark complete — results in $RESULTS_FILE ==="