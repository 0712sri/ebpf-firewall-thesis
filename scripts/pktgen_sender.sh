#!/usr/bin/env bash
# scripts/pktgen_sender.sh
# Runs on xdp-sender — sends UDP packets toward xdp-receiver via xdp-firewall
# Topology: xdp-sender (192.168.1.2) → xdp-firewall → xdp-receiver (192.168.2.2)
#
# Usage:
#   sudo bash scripts/pktgen_sender.sh <pps> <duration_sec> <pkt_size>
#   sudo bash scripts/pktgen_sender.sh 10000 30 64

set -euo pipefail

PPS=${1:-10000}
DURATION=${2:-30}
PKT_SIZE=${3:-64}
IFACE=eth1
DST_IP=192.168.2.2
DST_MAC=bc:24:11:8e:2c:cb  # xdp-firewall ens19 (next hop)
THREAD=kpktgend_0

# Calculate delay in nanoseconds from PPS
# delay = 1,000,000,000 / PPS
DELAY=$(python3 -c "print(int(1000000000 / $PPS))")

echo "[pktgen] PPS=$PPS  Duration=${DURATION}s  PktSize=${PKT_SIZE}B  Delay=${DELAY}ns"

sudo modprobe pktgen 2>/dev/null || true

sudo bash -c "
echo 'rem_device_all'      > /proc/net/pktgen/$THREAD
echo 'add_device $IFACE'   > /proc/net/pktgen/$THREAD
echo 'count 0'             > /proc/net/pktgen/$IFACE
echo 'delay $DELAY'        > /proc/net/pktgen/$IFACE
echo 'pkt_size $PKT_SIZE'  > /proc/net/pktgen/$IFACE
echo 'dst $DST_IP'         > /proc/net/pktgen/$IFACE
echo 'dst_mac $DST_MAC'    > /proc/net/pktgen/$IFACE
echo 'udp_src_min 1024'    > /proc/net/pktgen/$IFACE
echo 'udp_src_max 65535'   > /proc/net/pktgen/$IFACE
echo 'udp_dst_min 5001'    > /proc/net/pktgen/$IFACE
echo 'udp_dst_max 5001'    > /proc/net/pktgen/$IFACE
"

sudo bash -c "echo 'start' > /proc/net/pktgen/pgctrl" &
sleep "$DURATION"
sudo bash -c "echo 'stop' > /proc/net/pktgen/pgctrl"

echo ""
echo "=== pktgen results ==="
sudo cat /proc/net/pktgen/$IFACE | grep -E "Result|pps|pkts-sofar|errors"
