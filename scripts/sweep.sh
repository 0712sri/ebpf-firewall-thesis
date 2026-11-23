#!/usr/bin/env bash
# scripts/sweep.sh — many fwexp.sh runs in one command. Runs on apt-kitten.
#
# Usage: bash scripts/sweep.sh [reps] [pps] [count] ["configs"] ["positions"]
#   defaults: 10 reps, 30000 pps, 300000 packets (10 s), all configs, all positions
#   e.g. bash scripts/sweep.sh                       # the full run (~45 min)
#        bash scripts/sweep.sh 1 30000 30000         # quick check (~5 min)
#        bash scripts/sweep.sh 10 30000 300000 "b1 b2" "best miss"
#
# Every repetition runs all config x position pairs once, in a NEW random
# order, so slow drift (temperature, other load) hits all configs equally.
# All rows go to one CSV per sweep: ~/srinika/results/sweep_<start time>.csv
# A failed run is logged and skipped; the sweep goes on.
# Run it inside tmux/screen (or nohup) so it survives a lost SSH connection.

set -uo pipefail
cd "$(dirname "$0")/.."

REPS=${1:-10}
PPS=${2:-30000}
COUNT=${3:-300000}
CONFIGS=${4:-"a b0 b1 b2"}
POSITIONS=${5:-"best middle worst miss"}

STAMP=$(date +%Y%m%d_%H%M%S)
export RESULTS=$HOME/srinika/results/sweep_$STAMP.csv
LOG=$HOME/srinika/results/sweep_$STAMP.log
mkdir -p "$(dirname "$RESULTS")"

pairs=()
for c in $CONFIGS; do for p in $POSITIONS; do pairs+=("$c $p"); done; done
total=$(( REPS * ${#pairs[@]} ))
echo "[sweep] $total runs: $REPS reps x ${#pairs[@]} pairs, $PPS pps, $COUNT pkts -> $RESULTS" | tee "$LOG"

n=0; ok=0
for rep in $(seq 1 "$REPS"); do
    while read -r c p; do
        n=$((n + 1))
        if REP=$rep bash scripts/fwexp.sh "$c" "$p" "$PPS" "$COUNT" >> "$LOG" 2>&1; then
            ok=$((ok + 1)); status=ok
        else
            status=FAILED
        fi
        echo "[$n/$total] rep $rep  $c $p  $status" | tee -a "$LOG"
    done < <(printf '%s\n' "${pairs[@]}" | shuf)
done

echo "[sweep] done: $ok/$total ok -> $RESULTS" | tee -a "$LOG"
