#!/usr/bin/env bash
set -euo pipefail
CONFIG=${1:-b2}; IFACE=${2:-ens3}; TARGET=${3:-10.8.50.178}; DUR=${4:-30}
mkdir -p bench
TS=$(date +%Y%m%d_%H%M%S)
OUT="bench/results_${CONFIG}_${TS}.csv"
case "$CONFIG" in
  counter) sudo bash scripts/tc_attach.sh attach "$IFACE" obj/pkt_counter.bpf.o tc ;;
  b1)      sudo bash scripts/tc_attach.sh attach "$IFACE" obj/firewall_b1.bpf.o tc ;;
  b2)      sudo bash scripts/tc_attach.sh attach "$IFACE" obj/firewall_b2.bpf.o tc ;;
  none)    sudo bash scripts/tc_attach.sh detach "$IFACE" 2>/dev/null || true ;;
esac
sleep 1
echo "timestamp,config,pps,cpu_pct" > "$OUT"
CPU_B=$(grep '^cpu ' /proc/stat | awk '{t=0;for(i=2;i<=NF;i++)t+=$i; print t,$5}')
sleep "$DUR"
CPU_A=$(grep '^cpu ' /proc/stat | awk '{t=0;for(i=2;i<=NF;i++)t+=$i; print t,$5}')
CPU=$(python3 -c "
b='${CPU_B}'.split(); a='${CPU_A}'.split()
dt=int(a[0])-int(b[0]); di=int(a[1])-int(b[1])
print(f'{(1-di/dt)*100:.1f}' if dt else '0')
")
echo "$TS,$CONFIG,0,$CPU" >> "$OUT"
echo "=== $CONFIG | CPU: ${CPU}% | $OUT ==="
sudo bash scripts/read_stats.sh 2>/dev/null || true
sudo bash scripts/tc_attach.sh detach "$IFACE"
