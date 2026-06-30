#!/usr/bin/env bash
set -euo pipefail
MAP_NAME=${1:-""}
if [[ -z "$MAP_NAME" ]]; then
    bpftool map list 2>/dev/null | grep -q "fw_stats"  && MAP_NAME=fw_stats  || true
    bpftool map list 2>/dev/null | grep -q "pkt_stats" && MAP_NAME=pkt_stats || true
fi
[[ -z "$MAP_NAME" ]] && { echo "No stats map found. Program loaded?"; exit 1; }
echo "=== $MAP_NAME ==="
sudo bpftool map dump name "$MAP_NAME" -j | python3 -c "
import sys, json
data = json.load(sys.stdin)
totals = {}
for e in data:
    f = e['formatted']
    k = f['key']
    total = sum(v['value'] for v in f['values'])
    totals[k] = totals.get(k, 0) + total
name = '$MAP_NAME'
if name == 'pkt_stats':
    print(f'  Packets : {totals.get(0,0):>12,}')
    print(f'  Bytes   : {totals.get(1,0):>12,}')
elif name == 'fw_stats':
    a  = totals.get(0, 0)
    d  = totals.get(1, 0)
    ab = totals.get(2, 0)
    db = totals.get(3, 0)
    print(f'  ACCEPT  pkts:{a:>10,}  bytes:{ab:>12,}')
    print(f'  DROP    pkts:{d:>10,}  bytes:{db:>12,}')
    print(f'  Drop rate: {d/(a+d)*100:.1f}%' if a+d else '  No packets yet')
"
