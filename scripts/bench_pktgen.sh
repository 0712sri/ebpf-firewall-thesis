#!/usr/bin/env bash
# scripts/bench_pktgen.sh
# Packet-processing benchmark using Linux pktgen,
# informed by Turull et al. (2016) and RFC 2544 frame-loss procedure.
#
# Measures per pktgen run:
#   - Offered packets (pktgen pkts-sofar)
#   - Forwarded packets (tcpdump count on ens20 — benchmark port only)
#   - Forwarded loss % = (offered - forwarded) / offered   [ACCEPT tests only]
#   - pktgen-reported achieved PPS
#   - pktgen run duration (generator elapsed time — NOT firewall processing time)
#   - pktgen errors (generator-side errors)
#   - Expected verdict (ACCEPT or DROP)
#
# Usage:
#   sudo bash scripts/bench_pktgen.sh <config> <rule_count> <match_pos> <verdict>
#
#   match_pos: best | middle | worst | miss
#   verdict:   accept | drop
#
# Examples:
#   sudo bash scripts/bench_pktgen.sh b2 10 best accept
#   sudo bash scripts/bench_pktgen.sh config_a 100 worst accept
#   sudo bash scripts/bench_pktgen.sh b2 10 miss drop
#
# Run on: xdp-sender

set -euo pipefail

CONFIG=${1:-unknown}
RULE_COUNT=${2:-10}
MATCH_POS=${3:-best}
VERDICT=${4:-accept}

# Fixed packet count per run — realistic for rate range used
# At 1k pps: 10k pkts = 10 seconds. At 30k pps: 10k pkts = 0.3 seconds.
# Use 30k packets for all runs — ~1-30 seconds depending on rate.
NUM_PKTS=30000
REPETITIONS=5
FIREWALL_HOST="xdp-firewall"
EGRESS_IFACE="ens20"
RESULTS_FILE="bench/pktgen_results.csv"
DST_IP="192.168.2.2"
PKTGEN_IFACE="eth1"
THREAD="kpktgend_0"
DST_MAC="bc:24:11:8e:2c:cb"

# Packet sizes (bytes) — covers full range per RFC 2544
PACKET_SIZES=(64 128 256 512 1024 1518)

# Offered rates (pps) — sweep from low to above NIC ceiling
# Fine-grained around known saturation region (~32k pps)
RATES=(1000 5000 10000 15000 20000 25000 30000 35000 40000)

# Destination port determines which rule is matched
# Adjust these to match your actual ruleset order
case "$MATCH_POS" in
    best)   DST_PORT=80     ;;   # matches first ACCEPT rule
    middle) DST_PORT=5201   ;;   # matches middle ACCEPT rule
    worst)  DST_PORT=10000  ;;   # matches last ACCEPT rule
    miss)   DST_PORT=9999   ;;   # matches no rule → default DROP
    *)      echo "ERROR: match_pos must be best|middle|worst|miss"; exit 1 ;;
esac

# Write CSV header only if file does not exist
if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,config,rule_count,match_pos,dst_port,expected_verdict,pkt_size_bytes,target_pps,offered_pkts,pktgen_errors,pktgen_achieved_pps,pktgen_duration_us,forwarded_pkts,forwarded_loss_pct,repetition" > "$RESULTS_FILE"
fi

echo "========================================================"
echo " Firewall Benchmark (Turull et al. 2016 / RFC 2544)"
echo "========================================================"
echo " Config:          $CONFIG"
echo " Rule count:      $RULE_COUNT"
echo " Match position:  $MATCH_POS (dst_port=$DST_PORT)"
echo " Expected verdict:$VERDICT"
echo " Packets/run:     $NUM_PKTS"
echo " Repetitions:     $REPETITIONS"
echo " Packet sizes:    ${PACKET_SIZES[*]} bytes"
echo " Rates (pps):     ${RATES[*]}"
echo "========================================================"

sudo modprobe pktgen 2>/dev/null || true

for PKT_SIZE in "${PACKET_SIZES[@]}"; do
    for PPS in "${RATES[@]}"; do
        for REP in $(seq 1 $REPETITIONS); do

            echo ""
            echo "--- PktSize=${PKT_SIZE}B  Rate=${PPS}pps  Rep=${REP}/${REPETITIONS} ---"

            # Start tcpdump on xdp-firewall ens20 counting only benchmark packets
            # Count UDP packets with specific dst port — excludes all other traffic
            TCPDUMP_PID=""
            TCPDUMP_FILE="/tmp/bench_fwd_${PKT_SIZE}_${PPS}_${REP}.txt"

            ssh "$FIREWALL_HOST" "sudo tcpdump -i $EGRESS_IFACE -c 1000000 \
                udp dst port $DST_PORT -w /tmp/bench_cap.pcap 2>/tmp/tcpdump_err.txt &
                echo \$!" > /tmp/remote_pid.txt
            REMOTE_PID=$(cat /tmp/remote_pid.txt)
            sleep 0.5  # let tcpdump start

            # Configure pktgen — use ratep for native PPS control
            sudo bash -c "
echo 'rem_device_all'         > /proc/net/pktgen/$THREAD
echo 'add_device $PKTGEN_IFACE' > /proc/net/pktgen/$THREAD
echo 'count $NUM_PKTS'        > /proc/net/pktgen/$PKTGEN_IFACE
echo 'ratep $PPS'             > /proc/net/pktgen/$PKTGEN_IFACE
echo 'pkt_size $PKT_SIZE'     > /proc/net/pktgen/$PKTGEN_IFACE
echo 'dst $DST_IP'            > /proc/net/pktgen/$PKTGEN_IFACE
echo 'dst_mac $DST_MAC'       > /proc/net/pktgen/$PKTGEN_IFACE
echo 'udp_dst_min $DST_PORT'  > /proc/net/pktgen/$PKTGEN_IFACE
echo 'udp_dst_max $DST_PORT'  > /proc/net/pktgen/$PKTGEN_IFACE
echo 'udp_src_min 1024'       > /proc/net/pktgen/$PKTGEN_IFACE
echo 'udp_src_max 65535'      > /proc/net/pktgen/$PKTGEN_IFACE
echo 'start'                  > /proc/net/pktgen/pgctrl
"
            # Stop tcpdump on firewall and count forwarded packets
            ssh "$FIREWALL_HOST" "sudo kill $REMOTE_PID 2>/dev/null; \
                sleep 0.5; \
                sudo tcpdump -r /tmp/bench_cap.pcap udp dst port $DST_PORT 2>/dev/null | wc -l" \
                > "$TCPDUMP_FILE" 2>/dev/null || echo "0" > "$TCPDUMP_FILE"

            FORWARDED=$(cat "$TCPDUMP_FILE" | tail -1 | tr -d ' ')

            # Parse pktgen results
            RESULT=$(sudo cat /proc/net/pktgen/$PKTGEN_IFACE)
            OFFERED=$(echo "$RESULT" | grep "pkts-sofar" | grep -oP '\d+' | head -1)
            PKTGEN_ERRORS=$(echo "$RESULT" | grep "errors:" | tail -1 | grep -oP 'errors: \d+' | grep -oP '\d+' || echo "0")
            ACHIEVED_PPS=$(echo "$RESULT" | grep -oP '\d+pps' | head -1 | grep -oP '\d+' || echo "0")
            DURATION=$(echo "$RESULT" | grep "Result:" | grep -oP '\d+(?=\()' | head -1 || echo "0")

            # Calculate forwarded loss % — only meaningful for ACCEPT tests
            if [ "$VERDICT" = "accept" ] && [ "${OFFERED:-0}" -gt 0 ]; then
                LOSS_PCT=$(python3 -c "
offered=${OFFERED:-0}
fwd=${FORWARDED:-0}
lost=offered-fwd
pct=(lost/offered)*100 if offered>0 else 0
print(f'{pct:.4f}')
")
            else
                # DROP test — egress=0 is correct behaviour, not loss
                LOSS_PCT="N/A (DROP test)"
            fi

            TIMESTAMP=$(date +%Y%m%d_%H%M%S)

            # Write to CSV
            echo "${TIMESTAMP},${CONFIG},${RULE_COUNT},${MATCH_POS},${DST_PORT},${VERDICT},${PKT_SIZE},${PPS},${OFFERED:-0},${PKTGEN_ERRORS:-0},${ACHIEVED_PPS:-0},${DURATION:-0},${FORWARDED:-0},${LOSS_PCT},${REP}" >> "$RESULTS_FILE"

            echo "  Offered:      ${OFFERED:-0} pkts"
            echo "  pktgen errors:${PKTGEN_ERRORS:-0}"
            echo "  Achieved PPS: ${ACHIEVED_PPS:-0}"
            echo "  Duration:     ${DURATION:-0} us  (generator elapsed time)"
            echo "  Forwarded:    ${FORWARDED:-0} pkts  (ens20, dst_port=$DST_PORT only)"
            echo "  Loss:         ${LOSS_PCT}"

            # Clean up temp files
            rm -f "$TCPDUMP_FILE" /tmp/remote_pid.txt
            ssh "$FIREWALL_HOST" "sudo rm -f /tmp/bench_cap.pcap /tmp/tcpdump_err.txt" 2>/dev/null || true

            # Cool down between runs
            sleep 3
        done
    done
done

echo ""
echo "=== Benchmark complete — results in $RESULTS_FILE ==="