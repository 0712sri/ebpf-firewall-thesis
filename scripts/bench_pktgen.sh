#!/usr/bin/env bash
# scripts/bench_pktgen.sh
# Systematic benchmark following Turull et al. 2016 pktgen methodology
# Tests multiple packet sizes at controlled rates below NIC ceiling
# Run on xdp-sender
#
# Usage: sudo bash scripts/bench_pktgen.sh <config_name>
# Example: sudo bash scripts/bench_pktgen.sh b2

set -euo pipefail

CONFIG=${1:-unknown}
NUM_PKTS=100000
RESULTS_FILE="bench/pktgen_results.csv"

# Packet sizes per RFC 2544 methodology
PACKET_SIZES=(64 512 1280 1518)

# Rates well below NIC ceiling (~32K pps)
RATES=(1000 5000 10000 20000)

echo "timestamp,config,pkt_size,target_pps,actual_pps,num_pkts,errors,duration_us" >> $RESULTS_FILE

for PKT_SIZE in "${PACKET_SIZES[@]}"; do
    for PPS in "${RATES[@]}"; do
        echo ""
        echo "=== Config=$CONFIG PktSize=${PKT_SIZE}B Rate=${PPS}pps ==="

        # Run pktgen
        sudo bash scripts/pktgen_sender.sh $PPS $PKT_SIZE $NUM_PKTS

        # Parse results
        RESULT=$(sudo cat /proc/net/pktgen/eth1)
        ACTUAL_PPS=$(echo "$RESULT" | grep -oP '\d+pps' | grep -oP '\d+')
        ERRORS=$(echo "$RESULT" | grep -oP 'errors: \d+' | grep -oP '\d+')
        DURATION=$(echo "$RESULT" | grep -oP '\d+(?=\()' | head -1)

        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        echo "${TIMESTAMP},${CONFIG},${PKT_SIZE},${PPS},${ACTUAL_PPS},${NUM_PKTS},${ERRORS},${DURATION}" >> $RESULTS_FILE

        echo "Result: ${ACTUAL_PPS}pps errors=${ERRORS} duration=${DURATION}us"

        # Cool down between runs
        sleep 2
    done
done

echo ""
echo "=== Benchmark complete — results in $RESULTS_FILE ==="
