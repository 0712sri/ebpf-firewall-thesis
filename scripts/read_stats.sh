#!/usr/bin/env bash
set -euo pipefail
MAP_NAME=${1:-""}
if [[ -z "$MAP_NAME" ]]; then
    bpftool map list 2>/dev/null | grep -q "fw_stats"  && MAP_NAME=fw_stats  || true
    bpftool map list 2>/dev/null | grep -q "pkt_stats" && MAP_NAME=pkt_stats || true
fi
[[ -z "$MAP_NAME" ]] && { echo "No stats map found. Program loaded?"; exit 1; }
MAP_ID=$(bpftool map list 2>/dev/null | awk -F: "/name $MAP_NAME/"'{print $1}' | head -1)
[[ -z "$MAP_ID" ]] && { echo "Map $MAP_NAME not found"; exit 1; }
echo "=== $MAP_NAME (id=$MAP_ID) ==="
DUMP=$(bpftool map dump id "$MAP_ID" -j 2>/dev/null)
python3 - "$MAP_NAME" "$DUMP" << 'PYEOF'
import sys, json
name, data = sys.argv[1], json.loads(sys.argv[2])
totals = {}
for e in data:
    k = int(e["key"],16) if isinstance(e["key"],str) else e["key"]
    vs = e.get("values", [e.get("value",0)])
    totals[k] = totals.get(k,0) + sum(int(v,16) if isinstance(v,str) else v for v in (vs if isinstance(vs,list) else [vs]))
if name == "pkt_stats":
    print(f"  Packets : {totals.get(0,0):>12,}")
    print(f"  Bytes   : {totals.get(1,0):>12,}")
elif name == "fw_stats":
    a,d,ab,db = totals.get(0,0),totals.get(1,0),totals.get(2,0),totals.get(3,0)
    print(f"  ACCEPT  pkts:{a:>10,}  bytes:{ab:>12,}")
    print(f"  DROP    pkts:{d:>10,}  bytes:{db:>12,}")
    print(f"  Drop rate: {d/(a+d)*100:.1f}%" if a+d else "  No packets yet")
PYEOF
