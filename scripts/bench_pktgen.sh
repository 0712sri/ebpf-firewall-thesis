#!/usr/bin/env bash
# scripts/bench_pktgen.sh
# Packet-processing benchmark informed by Turull et al. (2016) and RFC 2544.
# Run on: xdp-sender
#
# BEFORE running: on xdp-firewall run:
#   sudo bash scripts/setup_benchmark.sh <config> <rule_count> <dst_port>
#
# Usage:
#   sudo bash scripts/bench_pktgen.sh <config> <rule_count> <match_pos> <verdict>
#
# Examples:
#   sudo bash scripts/bench_pktgen.sh b2 10 best accept
#   sudo bash scripts/bench_pktgen.sh b1 10 worst accept
#   sudo bash scripts/bench_pktgen.sh config_a 10 miss drop

set -euo pipefail

CONFIG=${1:-unknown}
RULE_COUNT=${2:-10}
MATCH_POS=${3:-best}
VERDICT=${4:-accept}
RESULTS_FILE="bench/pktgen_results.csv"

case "$MATCH_POS" in
    best)   DST_PORT=80   ;;
    middle) DST_PORT=5500 ;;
    worst)  DST_PORT=9900 ;;
    miss)   DST_PORT=9999 ;;
    *) echo "ERROR: match_pos must be best|middle|worst|miss"; exit 1 ;;
esac

PACKET_SIZES=(64 128 256 512 1024)
RATES=(10000 20000 30000 40000 50000)
REPETITIONS=3
DURATION_S=10

if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,config,rule_count,match_pos,dst_port,expected_verdict,pkt_size_bytes,target_pps,offered_pkts,pktgen_errors,pktgen_achieved_pps,pktgen_duration_us,forwarded_pkts,forwarded_loss_pct,repetition" > "$RESULTS_FILE"
fi

echo "========================================================"
echo " Firewall Benchmark Setup"
echo "========================================================"
echo " Config:    $CONFIG  |  Rules: $RULE_COUNT"
echo " Match pos: $MATCH_POS (port=$DST_PORT)  |  Verdict: $VERDICT"
echo " Sizes:     ${PACKET_SIZES[*]} bytes"
echo " Rates:     ${RATES[*]} pps"
echo " Duration:  ${DURATION_S}s per trial  |  Reps: $REPETITIONS"
echo "========================================================"
echo ""
echo "  On xdp-firewall run:"
echo "   sudo bash scripts/setup_benchmark.sh $CONFIG $RULE_COUNT $DST_PORT"
echo ""
read -p "Press ENTER when xdp-firewall is ready..."

sudo modprobe pktgen 2>/dev/null || true

for PKT_SIZE in "${PACKET_SIZES[@]}"; do
    for PPS in "${RATES[@]}"; do

        NUM_PKTS=$(( PPS * DURATION_S ))

        for REP in $(seq 1 $REPETITIONS); do

            echo ""
            echo "--- Size=${PKT_SIZE}B  Rate=${PPS}pps  Rep=${REP}/${REPETITIONS}  Pkts=$NUM_PKTS ---"
            echo "  On xdp-firewall: sudo bash scripts/reset_counter.sh $DST_PORT"
            read -p "Press ENTER when counter is reset..."

            # Run pktgen
            sudo bash scripts/pktgen_sender.sh $PPS $PKT_SIZE $NUM_PKTS $DST_PORT

            # Parse pktgen results
            RESULT=$(sudo cat /proc/net/pktgen/eth1)
            OFFERED=$(echo "$RESULT" | grep "pkts-sofar" | grep -oP '\d+' | head -1)
            PKTGEN_ERRORS=$(echo "$RESULT" | grep "errors:" | tail -1 | grep -oP 'errors: \d+' | grep -oP '\d+' || echo "0")
            ACHIEVED_PPS=$(echo "$RESULT" | grep -oP '\d+pps' | head -1 | grep -oP '\d+' || echo "0")
            DURATION=$(echo "$RESULT" | grep "Result:" | grep -oP '\d+(?=\()' | head -1 || echo "0")

            echo ""
            echo "  Offered:  ${OFFERED:-0} pkts"
            echo "  PPS:      ${ACHIEVED_PPS:-0}"
            echo "  Duration: ${DURATION:-0} us"
            echo "  Errors:   ${PKTGEN_ERRORS:-0}"
            echo ""
            echo "  On xdp-firewall: sudo bash scripts/read_fwd_counter.sh"
            read -p "Enter forwarded packet count: " FORWARDED

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
            echo "${TIMESTAMP},${CONFIG},${RULE_COUNT},${MATCH_POS},${DST_PORT},${VERDICT},${PKT_SIZE},${PPS},${OFFERED:-0},${PKTGEN_ERRORS:-0},${ACHIEVED_PPS:-0},${DURATION:-0},${FORWARDED:-0},${LOSS_PCT},${REP}" >> "$RESULTS_FILE"

            echo "  Forwarded: $FORWARDED  |  Loss: $LOSS_PCT"
            sleep 1
        done
    done
done

echo ""
echo "=== Benchmark complete — results in $RESULTS_FILE ==="