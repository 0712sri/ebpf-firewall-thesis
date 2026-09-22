#!/usr/bin/env bash
# scripts/profile_benchmark.sh
# Measures BPF program cycles/packet using bpftool prog profile
# Run on: xdp-firewall
# Requires: traffic running from xdp-sender during measurement
#
# Usage: sudo bash scripts/profile_benchmark.sh <config> <prog_id> <repetitions> <duration>
#
# Example:
#   sudo bash scripts/profile_benchmark.sh b2 7526 5 15
#   sudo bash scripts/profile_benchmark.sh b1 7566 5 15

set -euo pipefail

CONFIG=${1:-b2}
PROG_ID=${2}
REPS=${3:-5}
DURATION=${4:-15}
BPFTOOL=/tmp/bpftool/src/bpftool
RESULTS_FILE="bench/profile_results.csv"

if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,config,prog_id,prog_name,duration_s,run_cnt,total_cycles,total_instructions,cycles_per_packet,instructions_per_packet,ipc,repetition" > "$RESULTS_FILE"
fi

# Get program name
PROG_NAME=$(sudo $BPFTOOL prog list id $PROG_ID 2>/dev/null | grep -oP 'name \K\S+' || echo "unknown")

echo "========================================================"
echo " BPF Profile Benchmark"
echo "========================================================"
echo " Config:     $CONFIG"
echo " Program:    $PROG_NAME (id=$PROG_ID)"
echo " Duration:   ${DURATION}s per trial"
echo " Repetitions: $REPS"
echo "========================================================"
echo ""
echo "⚠  Start continuous pktgen on xdp-sender NOW:"
echo "   for i in {1..20}; do sudo bash scripts/pktgen_sender.sh 30000 64 300000 80; done"
echo ""
read -p "Press ENTER when pktgen is running..."

for REP in $(seq 1 $REPS); do
    echo ""
    echo "--- Rep $REP/$REPS ---"

    # Run profile
    RESULT=$(sudo $BPFTOOL prog profile id $PROG_ID duration $DURATION cycles instructions 2>&1)
    echo "$RESULT"

    # Parse results
    RUN_CNT=$(echo "$RESULT" | grep "run_cnt" | grep -oP '\d+' | head -1)
    CYCLES=$(echo "$RESULT" | grep "cycles" | grep -oP '^\s+\d+' | grep -oP '\d+' | head -1)
    INSTRUCTIONS=$(echo "$RESULT" | grep "instructions" | grep -oP '^\s+\d+' | grep -oP '\d+' | head -1)

    if [ "${RUN_CNT:-0}" -gt 0 ]; then
        CYCLES_PER_PKT=$(python3 -c "print(f'{int('${CYCLES:-0}')/int('${RUN_CNT}'):.2f}')")
        INSNS_PER_PKT=$(python3 -c "print(f'{int('${INSTRUCTIONS:-0}')/int('${RUN_CNT}'):.2f}')")
        IPC=$(python3 -c "print(f'{int('${INSTRUCTIONS:-0}')/max(int('${CYCLES:-1}'),1):.4f}')")
    else
        CYCLES_PER_PKT="N/A"
        INSNS_PER_PKT="N/A"
        IPC="N/A"
        echo "  ⚠ run_cnt=0 — no traffic during profile window"
    fi

    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    echo "${TIMESTAMP},${CONFIG},${PROG_ID},${PROG_NAME},${DURATION},${RUN_CNT:-0},${CYCLES:-0},${INSTRUCTIONS:-0},${CYCLES_PER_PKT},${INSNS_PER_PKT},${IPC},${REP}" >> "$RESULTS_FILE"

    echo "  run_cnt:          ${RUN_CNT:-0}"
    echo "  cycles/packet:    ${CYCLES_PER_PKT}"
    echo "  insns/packet:     ${INSNS_PER_PKT}"
    echo "  IPC:              ${IPC}"

    sleep 2
done

echo ""
echo "=== Profile complete — results in $RESULTS_FILE ==="
