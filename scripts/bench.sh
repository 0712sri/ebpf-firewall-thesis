#!/usr/bin/env bash
# scripts/bench.sh
# Controlled pktgen benchmark for one config.
#
# Usage:
#   sudo bash scripts/bench.sh <config> <pkt_size> <duration_sec>
#
# Examples:
#   sudo bash scripts/bench.sh bare    64  30
#   sudo bash scripts/bench.sh b2     64  30
#   sudo bash scripts/bench.sh b1     64  30
#   sudo bash scripts/bench.sh config_a 64  30
#
# Output: bench/results.csv (appended)

set -euo pipefail

CONFIG=${1:-bare}
PKT_SIZE=${2:-64}
DURATION=${3:-30}
IFACE=eth1
DST_IP=10.35.5.2
DST_MAC=bc:24:11:f8:86:f9
RESULTS=bench/results.csv
THREAD=kpktgend_0

mkdir -p bench

# ── Write CSV header if file is new ──────────────────────────────────────────
if [[ ! -f "$RESULTS" ]]; then
    echo "timestamp,config,pkt_size,duration_s,pps,mbps,cpu_pct" > "$RESULTS"
fi

# ── Attach firewall if needed ─────────────────────────────────────────────────
echo "[bench] Config=$CONFIG  PktSize=${PKT_SIZE}B  Duration=${DURATION}s"

case "$CONFIG" in
    bare)
        sudo bash scripts/tc_attach.sh detach "$IFACE" 2>/dev/null || true
        ;;
   b1)
    sudo ./obj/b1_loader "$IFACE" &
    B1_PID=$!
    sleep 2  # wait for loader to attach
    ;;
    b2)
        sudo bash scripts/tc_attach.sh attach "$IFACE" obj/firewall_b2.bpf.o tc
        ;;
    config_a)
    sudo bash scripts/config_a_setup.sh load
    ;;
    *)
        echo "Unknown config: $CONFIG"; exit 1
        ;;
esac

sleep 1  # let program settle

# ── Set up pktgen ─────────────────────────────────────────────────────────────
sudo bash -c "
echo 'rem_device_all' > /proc/net/pktgen/$THREAD
echo 'add_device $IFACE' > /proc/net/pktgen/$THREAD
echo 'count 0'          > /proc/net/pktgen/$IFACE
echo 'delay 0'          > /proc/net/pktgen/$IFACE
echo 'pkt_size $PKT_SIZE' > /proc/net/pktgen/$IFACE
echo 'dst $DST_IP'      > /proc/net/pktgen/$IFACE
echo 'dst_mac $DST_MAC' > /proc/net/pktgen/$IFACE
"

# ── CPU baseline ──────────────────────────────────────────────────────────────
CPU_B=$(grep '^cpu ' /proc/stat | awk '{t=0; for(i=2;i<=NF;i++) t+=$i; print t, $5}')

# ── Run ───────────────────────────────────────────────────────────────────────
echo "[bench] Running..."
sudo bash -c "echo 'start' > /proc/net/pktgen/pgctrl" &
sleep "$DURATION"
sudo bash -c "echo 'stop' > /proc/net/pktgen/pgctrl"

# ── CPU after ─────────────────────────────────────────────────────────────────
CPU_A=$(grep '^cpu ' /proc/stat | awk '{t=0; for(i=2;i<=NF;i++) t+=$i; print t, $5}')

# ── Parse results ─────────────────────────────────────────────────────────────
RESULT=$(sudo cat /proc/net/pktgen/"$IFACE")
PPS=$(echo "$RESULT"  | grep -oP '\d+(?=pps)')
MBPS=$(echo "$RESULT" | grep -oP '\d+(?=Mb/sec)')

CPU=$(python3 -c "
b='${CPU_B}'.split(); a='${CPU_A}'.split()
dt=int(a[0])-int(b[0]); di=int(a[1])-int(b[1])
print(f'{(1-di/dt)*100:.1f}' if dt else '0')
")

TS=$(date +%Y%m%d_%H%M%S)
echo "$TS,$CONFIG,$PKT_SIZE,$DURATION,${PPS:-0},${MBPS:-0},$CPU" >> "$RESULTS"

# ── Print summary ─────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
echo "  Config   : $CONFIG"
echo "  Pkt size : ${PKT_SIZE}B"
echo "  PPS      : ${PPS:-0}"
echo "  Mbps     : ${MBPS:-0}"
echo "  CPU      : ${CPU}%"
echo "  Results  : $RESULTS"
echo "════════════════════════════════════"

# ── Show firewall stats if loaded ────────────────────────────────────────────
sudo bash scripts/read_stats.sh fw_stats 2>/dev/null || true

# ── Detach firewall ───────────────────────────────────────────────────────────
# Detach — kill b1_loader if running, otherwise use tc detach
if [[ -n "${B1_PID:-}" ]]; then
    sudo kill "$B1_PID" 2>/dev/null || true
    wait "$B1_PID" 2>/dev/null || true
else
    sudo bash scripts/tc_attach.sh detach "$IFACE" 2>/dev/null || true
fi
sudo bash scripts/config_a_setup.sh flush 2>/dev/null || true