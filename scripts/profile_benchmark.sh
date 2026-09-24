#!/usr/bin/env bash
# scripts/profile_benchmark.sh
# Measures BPF program cycles/packet using bpftool prog profile
# Run on: xdp-firewall
# Requires: traffic running from xdp-sender during measurement
# Example:
# Usage: sudo bash scripts/profile_benchmark.sh <config> <prog_id> <match_port> <repetitions> <duration>
#   sudo bash scripts/profile_benchmark.sh b2 7920 80 5 15    (best case)
#   sudo bash scripts/profile_benchmark.sh b2 7920 9900 5 15  (worst case)
#   sudo bash scripts/profile_benchmark.sh b1 7811 80 5 15    (best case)

set -u

CONFIG=${1:-b2}
PROG_ID=${2}
MATCH_PORT=${3:-80}
REPS=${4:-5}
DURATION=${5:-15}
BPFTOOL=/tmp/bpftool/src/bpftool
RESULTS_FILE="bench/profile_results.csv"

if [ ! -f "$RESULTS_FILE" ]; then
    echo "timestamp,config,prog_id,prog_name,duration_s,run_cnt,total_cycles,total_instructions,cycles_per_packet,instructions_per_packet,ipc,repetition" > "$RESULTS_FILE"
fi

# Get program name
PROG_NAME=$(sudo $BPFTOOL prog list id $PROG_ID 2>/dev/null | head -1 | awk '{print $4}' | tr -d '\n' || echo "prog_${PROG_ID}")


echo "========================================================"
echo " BPF Profile Benchmark"
echo "========================================================"
echo " Config:     $CONFIG"
echo " Program:    $PROG_NAME (id=$PROG_ID)"
echo " Duration:   ${DURATION}s per trial"
echo " Repetitions: $REPS"
echo "========================================================"
echo ""
echo "   Start continuous pktgen on xdp-sender NOW:"
echo "   for i in {1..20}; do sudo bash scripts/pktgen_sender.sh 30000 64 300000 $MATCH_PORT; done"
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
                CYCLES_PER_PKT=$(python3 -c "print(f'{int('$CYCLES')/int('$RUN_CNT'):.2f}')" 2>/dev/null || python3 -c "print(round($CYCLES/$RUN_CNT, 2))")
                INSNS_PER_PKT=$(python3 -c "print(round($INSTRUCTIONS/$RUN_CNT, 2))")
                IPC=$(python3 -c "print(round($INSTRUCTIONS/max($CYCLES,1), 4))")
    else
        CYCLES_PER_PKT="N/A"
        INSNS_PER_PKT="N/A"
        IPC="N/A"
        echo "   run_cnt=0 — no traffic during profile window"
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
