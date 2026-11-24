#!/usr/bin/env bash
# scripts/run.sh — THE command. Runs on apt-kitten. One config (or all) -> one results folder.
#
# Usage: bash scripts/run.sh <a|b0|b1|b2|all> [reps] ["rule sizes"] [pps]
#   bash scripts/run.sh b2                    # B2: 10/100/1000 rules x best/middle/worst/miss x 15 reps
#   bash scripts/run.sh all                   # A, B0, B1, B2 mixed (recommended for final data)
#   bash scripts/run.sh b1 3 "100"            # quick: 3 reps, only 100 rules
#   bash scripts/run.sh all 5 "10" 140000     # high rate (near the 100 Mbit line rate)
#
# Each run of a config takes ~13 s (10 s traffic). One config with the defaults:
# 3 sizes x 4 positions x 15 reps = 180 runs = ~40 min; "all" = ~2.6 h. Use tmux.
#
# Output: ~/srinika/results/<config>_<date_time>/
#   results.csv   every run, one line each (the data for the thesis)
#   run.log       everything that happened
#   summary.txt   table per rule size and position: ns/packet, forwarded, CPU
#   hwinfo_*.txt  CPU, NIC, driver, kernel, IRQ affinity, offloads of both machines
# Under the hood: sweep.sh -> fwexp.sh -> (casual-lamb) fw_setup.sh / fw_stats.sh + pktgen_sender.sh

set -uo pipefail
cd "$(dirname "$0")/.."
export HOME=${HOME:-/home/ubuntu}

CFG=${1:?usage: run.sh <a|b0|b1|b2|all> [reps] [\"rule sizes\"] [pps]}
REPS=${2:-15}
SIZES=${3:-"10 100 1000"}
PPS=${4:-30000}
COUNT=$((PPS * 10))                      # 10 s of traffic per run
case "$CFG" in
    all) CONFIGS="a b0 b1 b2" ;;
    a|b0|b1|b2) CONFIGS=$CFG ;;
    *) echo "config must be a, b0, b1, b2 or all"; exit 1 ;;
esac

OUT=$HOME/srinika/results/${CFG}_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT"
LOG=$OUT/run.log
LAMB=ubuntu@casual-lamb.maasint.cl.bth.se

{
echo "[run] config=$CFG ($CONFIGS)  sizes=$SIZES  reps=$REPS  pps=$PPS  packets/run=$COUNT"
echo "[run] repo $(git rev-parse --short HEAD 2>/dev/null) on $(hostname), started $(date)"

# preflight: casual-lamb has the same code and built objects for every size, nothing active
lamb_rev=$(ssh -n -o BatchMode=yes "$LAMB" 'cd srinika/ebpf-firewall-thesis && git rev-parse --short HEAD')
[ "$lamb_rev" = "$(git rev-parse --short HEAD)" ] \
    || { echo "[run] STOP: casual-lamb is on $lamb_rev, apt-kitten on $(git rev-parse --short HEAD) -> git pull on both"; exit 1; }
for n in $SIZES; do
    ssh -n -o BatchMode=yes "$LAMB" "cd srinika/ebpf-firewall-thesis && ls obj/n$n/firewall_b0.bpf.o obj/n$n/firewall_b1.bpf.o obj/n$n/firewall_b2.bpf.o rules/config_a_$n.rules" >/dev/null \
        || { echo "[run] STOP: rule size $n not built on casual-lamb -> run make there"; exit 1; }
done
ssh -n -o BatchMode=yes "$LAMB" 'cd srinika/ebpf-firewall-thesis && sudo bash scripts/fw_setup.sh off' >/dev/null
echo "[run] preflight OK (both on $lamb_rev, objects for: $SIZES)"

# hardware/software documentation of both machines, stored with the results
ssh -o BatchMode=yes "$LAMB" 'bash -s' < scripts/hwinfo.sh > "$OUT/hwinfo_casual-lamb.txt" 2>&1
bash scripts/hwinfo.sh > "$OUT/hwinfo_apt-kitten.txt" 2>&1
echo "[run] hardware info saved (hwinfo_casual-lamb.txt, hwinfo_apt-kitten.txt)"

# the measurements: one sweep per rule size, configs and positions shuffled per rep
for n in $SIZES; do
    RESULTS_DIR=$OUT bash scripts/sweep.sh "$REPS" "$PPS" "$COUNT" "$CONFIGS" "best middle worst miss" "$n"
done
} 2>&1 | tee "$LOG"

# collect all rows into one CSV
first=1
for f in "$OUT"/sweep_*.csv; do
    [ -f "$f" ] || continue
    if [ $first = 1 ]; then cat "$f"; first=0; else tail -n +2 "$f"; fi
done > "$OUT/results.csv"
rm -f "$OUT"/sweep_*.csv            # all rows are in results.csv; the per-size logs stay

# summary table
python3 - "$OUT/results.csv" > "$OUT/summary.txt" <<'EOF'
import csv, sys, statistics as st, math
rows = list(csv.DictReader(open(sys.argv[1])))
if not rows:
    print("no results"); sys.exit()
T95 = {1: 12.71, 2: 4.30, 3: 3.18, 4: 2.78, 5: 2.57, 6: 2.45, 7: 2.36, 8: 2.31, 9: 2.26, 10: 2.23,
       11: 2.20, 12: 2.18, 13: 2.16, 14: 2.14, 15: 2.13, 16: 2.12, 17: 2.11, 18: 2.10, 19: 2.09}
def ci(v):
    if len(v) < 2: return 0.0
    return T95.get(len(v) - 1, 1.96) * st.stdev(v) / math.sqrt(len(v))
print(f"{'rules':>5} {'cfg':>3} {'position':>8} {'n':>3} {'ns/pkt (mean ± 95% CI)':>24} {'median':>7} "
      f"{'fwd/sent %':>10} {'cpu busy %':>10}")
key = lambda r: (int(r['rules']), r['config'], ['best', 'middle', 'worst', 'miss'].index(r['position']))
groups = {}
for r in rows:
    groups.setdefault(key(r), []).append(r)
for k in sorted(groups):
    g = groups[k]
    ns = [float(r['ns_per_pkt']) for r in g if r['ns_per_pkt']]
    fwd = 100 * sum(int(r['fwd']) for r in g) / max(1, sum(int(r['sent']) for r in g))
    cpu = st.mean(float(r['cpu_busy_pct']) for r in g if r['cpu_busy_pct'])
    nss = f"{st.mean(ns):8.1f} ± {ci(ns):5.1f}" if ns else "-"
    med = f"{st.median(ns):7.1f}" if ns else "-"
    print(f"{k[0]:>5} {k[1]:>3} {g[0]['position']:>8} {len(g):>3} {nss:>24} {med:>7} {fwd:>10.2f} {cpu:>10.2f}")
bad = [r for r in rows if (r['expected'] == 'drop') != (int(r['fwd']) == 0)]
print(f"\n{len(rows)} runs, {sum(int(r['tcfail'] or 0) for r in rows)} tail-call failures, "
      f"{len(bad)} runs with an unexpected verdict (forwarded on miss / nothing forwarded on accept)")
EOF

echo "[run] done -> $OUT" | tee -a "$LOG"
echo "      results.csv ($(($(wc -l < "$OUT/results.csv") - 1)) runs), summary.txt, run.log"
cat "$OUT/summary.txt"
