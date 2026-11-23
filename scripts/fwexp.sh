#!/usr/bin/env bash
# scripts/fwexp.sh — ONE experiment run. Runs on apt-kitten (NTAS command).
#
# Usage: bash fwexp.sh <a|b0|b1|b2> <best|middle|worst|miss> [pps] [count] [pkt_size]
#   e.g. bash fwexp.sh b2 best 30000 300000
#
#   1. sets up the config on casual-lamb       (fw_setup.sh)
#   2. reads the counters                      (fw_stats.sh read)
#   3. sends the traffic from here             (pktgen_sender.sh)
#   4. reads the counters again, prints ONE CSV line (also appended to results)
#   5. always cleans up: config off — even on error / Ctrl+C
#
# NTAS: select streams 010000010201 + 010000010202 to also get the MP captures.

set -euo pipefail
cd "$(dirname "$0")/.."

CFG=${1:?config: a|b0|b1|b2}
POS=${2:?position: best|middle|worst|miss}
PPS=${3:-30000}
COUNT=${4:-300000}
PKT_SIZE=${5:-64}
RULES=10                                     # rule set in src/fw_rules.h

LAMB=ubuntu@casual-lamb.maasint.cl.bth.se
REPO=srinika/ebpf-firewall-thesis            # relative to ~ on casual-lamb
RESULTS=${RESULTS:-$HOME/srinika/results/fwexp.csv}   # sweep.sh sets its own file
REP=${REP:-0}                                # set by sweep.sh

case "$POS" in
    best) PORT=80 ;; middle) PORT=5500 ;; worst) PORT=9900 ;; miss) PORT=9999 ;;
    *) echo "position must be best|middle|worst|miss"; exit 1 ;;
esac
case "$CFG" in a|b0|b1|b2) ;; *) echo "config must be a|b0|b1|b2"; exit 1 ;; esac

lamb() { ssh -o BatchMode=yes "$LAMB" "cd $REPO && $*"; }

cleanup() { lamb "sudo bash scripts/fw_setup.sh off" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# 1. config
lamb "sudo bash scripts/fw_setup.sh $CFG"
lamb "sudo bash scripts/fw_stats.sh prep $PORT"

# 2.-4. before / traffic / after
before=$(lamb "sudo bash scripts/fw_stats.sh read")
pg=$(sudo bash scripts/pktgen_sender.sh "$PPS" "$PKT_SIZE" "$COUNT" "$PORT")
sleep 1                                      # let in-flight packets drain
after=$(lamb "sudo bash scripts/fw_stats.sh read")
echo "$pg"

get()  { grep -oP "(^| )$1=\K\S+" <<<"$2" || echo 0; }
delta() { echo $(( $(get "$1" "$after") - $(get "$1" "$before") )); }

sent=$(grep -oP 'pkts-sofar: \K[0-9]+' <<<"$pg" || echo 0)
errs=$(grep -oP 'errors: \K[0-9]+' <<<"$pg" | tail -1 || echo 0)
usec=$(grep -oP 'Result: OK: \K[0-9]+' <<<"$pg" || echo 0)
run_cnt=$(delta run_cnt); run_ns=$(delta run_ns)
ns_pkt=$(awk -v n="$run_ns" -v c="$run_cnt" 'BEGIN{ if (c>0) printf "%.2f", n/c; else print "" }')
pct() { awk -v a="$1" -v b="$2" 'BEGIN{ if (b>0) printf "%.2f", 100*a/b; else print "" }'; }
cpu_total=$(delta cpu_total)
cpu_busy_pct=$(pct "$(delta cpu_busy)" "$cpu_total")      # all CPUs of casual-lamb
cpu_sirq_pct=$(pct "$(delta cpu_sirq)" "$cpu_total")
expected=$([ "$POS" = miss ] && [ "$CFG" != b0 ] && echo drop || echo accept)

header="timestamp,rep,config,rules,position,dst_port,expected,pps,pkt_size,sent,pktgen_errors,pktgen_usec,fwd,accept,drop,tcfail,a_accept,a_drop,run_cnt,run_ns,ns_per_pkt,cpu_busy_pct,cpu_softirq_pct,cpus"
line="$(date +%Y%m%d_%H%M%S),$REP,$CFG,$RULES,$POS,$PORT,$expected,$PPS,$PKT_SIZE,$sent,$errs,$usec,$(delta fwd),$(delta accept),$(delta drop),$(delta tcfail),$(delta a_accept),$(delta a_drop),$run_cnt,$run_ns,$ns_pkt,$cpu_busy_pct,$cpu_sirq_pct,$(get cpus "$after")"

mkdir -p "$(dirname "$RESULTS")"
[ -f "$RESULTS" ] || echo "$header" > "$RESULTS"
echo "$line" >> "$RESULTS"
echo "$header"
echo "$line"
echo "RESULT=OK"
