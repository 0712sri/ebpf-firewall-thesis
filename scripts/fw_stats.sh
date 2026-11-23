#!/usr/bin/env bash
# scripts/fw_stats.sh — read the measurement counters on casual-lamb
#
# Usage: sudo bash scripts/fw_stats.sh prep <dst_port>   # counter tracks <dst_port>, zeroed
#        sudo bash scripts/fw_stats.sh read              # one line of key=value
#
# read prints:
#   run_ns  run_cnt   bpf_stats of the attached entry program (B0/B1/B2; 0 for A)
#                     B1: chain_input's numbers include the tail-called chains
#   accept drop tcfail  fw_stats map of B0/B1/B2 (0 for A)
#   a_accept a_drop     iptables counters of config A (0 for B)
#   fwd               packets that left on the outgoing VLAN to <dst_port>
#   cpus              which CPU processed the packets, e.g. cpu3:2000
#   cpu_busy cpu_sirq cpu_total   CPU time of all CPUs from /proc/stat (jiffies):
#                     busy = user+nice+system+irq+softirq, sirq = softirq
#                     (packet processing runs in softirq), total = all states
# fwexp.sh reads it before and after the traffic and takes the difference.

set -euo pipefail
IFACE_IN=enp0s25.3155
BPFTOOL=/usr/sbin/bpftool

# map id of map <name> used by program <prog id>
map_of_prog() {
    $BPFTOOL -j prog show id "$1" | python3 -c '
import json, sys
for mid in json.load(sys.stdin).get("map_ids", []):
    print(mid)' | while read -r mid; do
        if [ "$($BPFTOOL -j map show id "$mid" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')" = "$2" ]; then echo "$mid"; fi
    done | head -1
}

# per-CPU array -> "key:total,..." and cpu totals
dump_percpu() {
    $BPFTOOL -j map dump id "$1" | python3 -c '
import json, sys
def num(v):
    return v if isinstance(v, int) else int.from_bytes(bytes(int(x, 16) for x in v), "little")
tot, cpus = {}, {}
for e in json.load(sys.stdin):
    f = e.get("formatted", e)
    k = num(f["key"])
    for c in f["values"]:
        v = num(c["value"]); tot[k] = tot.get(k, 0) + v
        if k in (0, 1): cpus[c["cpu"]] = cpus.get(c["cpu"], 0) + v
print(" ".join(f"k{k}={v}" for k, v in sorted(tot.items())),
      "cpus=" + (",".join(f"cpu{c}:{v}" for c, v in sorted(cpus.items()) if v) or "-"))'
}

case "${1:-read}" in
    prep)
        PORT=${2:?dst port}
        lo=$((PORT & 0xFF)); hi=$((PORT >> 8))
        $BPFTOOL map update name target_port_map key 0 0 0 0 value "$lo" "$hi"
        $BPFTOOL map update name fwd_counter key 0 0 0 0 value 0 0 0 0 0 0 0 0
        ;;
    read)
        run_ns=0; run_cnt=0; accept=0; drop=0; tcfail=0; cpus=-
        PROG=$(tc filter show dev "$IFACE_IN" ingress 2>/dev/null | grep -oP ' id \K[0-9]+' | head -1 || true)
        if [ -n "$PROG" ]; then
            info=$($BPFTOOL prog show id "$PROG")
            run_ns=$(grep -oP 'run_time_ns \K[0-9]+' <<<"$info" || echo 0)
            run_cnt=$(grep -oP 'run_cnt \K[0-9]+' <<<"$info" || echo 0)
            MID=$(map_of_prog "$PROG" fw_stats || true)
            if [ -n "$MID" ]; then
                d=$(dump_percpu "$MID")
                accept=$(grep -oP 'k0=\K[0-9]+' <<<"$d" || echo 0)
                drop=$(grep -oP 'k1=\K[0-9]+' <<<"$d" || echo 0)
                tcfail=$(grep -oP 'k2=\K[0-9]+' <<<"$d" || echo 0)
                cpus=$(grep -oP 'cpus=\K\S+' <<<"$d")
            fi
        fi
        # config A: packets accepted anywhere in ALLOW + dropped (FILTER_DROP + final DROP)
        chain_sum() { { iptables -L "$1" -v -x -n 2>/dev/null || true; } | awk -v t="$2" '$3==t{s+=$1} END{print s+0}'; }
        a_accept=$(chain_sum ALLOW ACCEPT)
        a_drop=$(( $(chain_sum FILTER_DROP DROP) + $(chain_sum FW_FORWARD DROP) ))
        CMID=$($BPFTOOL -j map show name fwd_counter 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else [d]; print(d[0]["id"] if d else "")' 2>/dev/null || true)
        fwd=0
        [ -n "$CMID" ] && fwd=$(dump_percpu "$CMID" | grep -oP 'k0=\K[0-9]+' || echo 0)
        read -r cpu_busy cpu_sirq cpu_total < <(awk '/^cpu /{b=$2+$3+$4+$7+$8; print b, $8, b+$5+$6+$9}' /proc/stat)
        echo "run_ns=$run_ns run_cnt=$run_cnt accept=$accept drop=$drop tcfail=$tcfail a_accept=$a_accept a_drop=$a_drop fwd=$fwd cpus=$cpus cpu_busy=$cpu_busy cpu_sirq=$cpu_sirq cpu_total=$cpu_total"
        ;;
    *)
        echo "Usage: $0 prep <port> | read"; exit 1 ;;
esac
